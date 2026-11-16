"""Step D: features + three models, leave-one-out CV, four pre-registered analyses.

Usage: python backtest.py
Writes results/step_d_results.md, results/step_d_predictions.csv, model.json.
"""
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

import series
from features import EARLY_WEEKS, MODEL_FEATURES, compute_features, still_rising

HERE = Path(__file__).parent
RESULTS_DIR = HERE / "results"
CLASSES = ["sustained", "spike"]

ANALYSES = [  # (key, description, multiplier, confirm_weeks, exclude_mid_trend)
    ("a", "Primary: all rows (3x, 2-week confirm)", 3.0, 2, False),
    ("b", "Excluding created_mid_trend rows (3x, 2-week)", 3.0, 2, True),
    ("c", "Robustness: 2x multiplier (2-week confirm)", 2.0, 2, False),
    ("d", "Original 1-week rule (3x, pre-amendment)", 3.0, 1, False),
]


# ---------- data ----------

def build_dataset(multiplier, confirm_weeks, exclude_mid_trend):
    rows = []
    for trend in series.load_trends():
        if exclude_mid_trend and trend["created_mid_trend"] == "yes":
            continue
        weekly = series.weekly_series(trend)
        onset, _ = series.detect_onset(weekly, multiplier=multiplier, confirm_weeks=confirm_weeks)
        if onset is None:
            continue
        label, _, _ = series.label_from_onset(weekly, onset)
        if label is None:
            continue
        values = weekly.to_numpy()
        rows.append({
            "name": trend["name"],
            "onset_week": (weekly.index[onset] - pd.Timedelta(days=6)).date(),
            "label": label,
            "still_rising": still_rising(values, onset),
            **compute_features(values, onset),
            "early_weeks": values[onset:onset + EARLY_WEEKS].tolist(),
        })
    return pd.DataFrame(rows)


# ---------- models ----------

def majority_predict(train_labels):
    counts = train_labels.value_counts()
    if len(counts) > 1 and counts.iloc[0] == counts.iloc[1]:
        return "spike"  # tie-break, amendment 2
    return counts.index[0]


def fit_logreg(X, y):
    model = make_pipeline(StandardScaler(), LogisticRegression())  # defaults: L2, C=1.0
    model.fit(X, y)
    return model


def loo_predictions(df):
    X = df[MODEL_FEATURES].to_numpy()
    y = (df["label"] == "sustained").astype(int).to_numpy()
    preds = {"majority": [], "naive": [], "logreg": [], "logreg_prob": []}
    for i in range(len(df)):
        train = np.arange(len(df)) != i
        preds["majority"].append(majority_predict(df["label"][train]))
        preds["naive"].append("sustained" if df["still_rising"].iloc[i] else "spike")
        if len(set(y[train])) < 2:  # can't fit with one class; predict it
            p = float(y[train][0])
        else:
            p = fit_logreg(X[train], y[train]).predict_proba(X[i:i + 1])[0, 1]
        preds["logreg_prob"].append(p)
        preds["logreg"].append("sustained" if p >= 0.5 else "spike")
    return preds


# ---------- metrics ----------

def wilson_ci(k, n, z=1.96):
    if n == 0:
        return (float("nan"), float("nan"))
    p = k / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (centre - half, centre + half)


def metrics(actual, predicted):
    actual, predicted = list(actual), list(predicted)
    n = len(actual)
    correct = sum(a == p for a, p in zip(actual, predicted))
    out = {"n": n, "correct": correct, "accuracy": correct / n, "ci": wilson_ci(correct, n)}
    for cls in CLASSES:
        tp = sum(a == cls and p == cls for a, p in zip(actual, predicted))
        pred_pos = sum(p == cls for p in predicted)
        actual_pos = sum(a == cls for a in actual)
        out[f"precision_{cls}"] = tp / pred_pos if pred_pos else None  # undefined: never predicted
        out[f"recall_{cls}"] = tp / actual_pos if actual_pos else None
    out["confusion"] = [[sum(a == ac and p == pc for a, p in zip(actual, predicted)) for pc in CLASSES]
                        for ac in CLASSES]
    return out


def fmt(x):
    return "n/a" if x is None else f"{x:.2f}"


def metrics_table(results):
    lines = ["| Model | Accuracy (k/n) | 95% CI | Prec sust. | Rec sust. | Prec spike | Rec spike | Confusion [[SS,SP],[PS,PP]] |",
             "|---|---|---|---|---|---|---|---|"]
    for model, m in results.items():
        lo, hi = m["ci"]
        lines.append(f"| {model} | {m['accuracy']:.2f} ({m['correct']}/{m['n']}) | {lo:.2f}–{hi:.2f} | "
                     f"{fmt(m['precision_sustained'])} | {fmt(m['recall_sustained'])} | "
                     f"{fmt(m['precision_spike'])} | {fmt(m['recall_spike'])} | {m['confusion']} |")
    return "\n".join(lines)


def df_to_markdown(df):
    """Tiny markdown table writer (avoids adding the tabulate dependency)."""
    cells = df.astype(object).where(df.notna(), "")
    lines = ["| " + " | ".join(df.columns) + " |", "|" + "---|" * len(df.columns)]
    lines += ["| " + " | ".join(str(v) for v in row) + " |" for row in cells.itertuples(index=False)]
    return "\n".join(lines)


# ---------- main ----------

def main():
    RESULTS_DIR.mkdir(exist_ok=True)
    report = ["# Step D results", "",
              "Leave-one-out CV. Confusion matrix rows = actual [sustained, spike], "
              "columns = predicted [sustained, spike]. Precision is n/a when a class was never predicted.", ""]
    all_preds = []
    primary_df = None

    for key, desc, multiplier, confirm, exclude in ANALYSES:
        df = build_dataset(multiplier, confirm, exclude)
        if key == "a":
            primary_df = df
        preds = loo_predictions(df)
        results = {m: metrics(df["label"], preds[m]) for m in ["majority", "naive", "logreg"]}
        counts = df["label"].value_counts().to_dict()

        report += [f"## ({key}) {desc}", "",
                   f"n = {len(df)} trends ({counts.get('sustained', 0)} sustained, {counts.get('spike', 0)} spike)"
                   + ("  **— too small to interpret (amendment 2)**" if key == "b" else ""), "",
                   metrics_table(results), ""]

        out = df[["name", "onset_week", "label"]].copy()
        out.insert(0, "analysis", key)
        out["majority"] = preds["majority"]
        out["naive"] = preds["naive"]
        out["logreg"] = preds["logreg"]
        out["logreg_prob_sustained"] = np.round(preds["logreg_prob"], 3)
        for f in MODEL_FEATURES + ["yoy_ratio"]:
            out[f] = df[f].round(3)
        all_preds.append(out)

    predictions = pd.concat(all_preds)
    predictions.to_csv(RESULTS_DIR / "step_d_predictions.csv", index=False)

    a = predictions[predictions.analysis == "a"]
    report += ["## Per-trend predictions, analysis (a)", "",
               df_to_markdown(a.drop(columns=["analysis"])), ""]
    (RESULTS_DIR / "step_d_results.md").write_text("\n".join(report))
    print("\n".join(report))

    export_model(primary_df)


def export_model(df):
    """Fit on all rows of (a) and write everything Rails needs to score with no Python."""
    X = df[MODEL_FEATURES].to_numpy()
    y = (df["label"] == "sustained").astype(int).to_numpy()
    model = fit_logreg(X, y)
    scaler, logreg = model.named_steps["standardscaler"], model.named_steps["logisticregression"]
    payload = {
        "description": "Logistic regression P(sustained) on standardized early-window features. "
                       "z = (x - mean) / scale; p = 1 / (1 + exp(-(intercept + sum(coef * z)))).",
        "features": MODEL_FEATURES,
        "scaler_mean": scaler.mean_.tolist(),
        "scaler_scale": scaler.scale_.tolist(),
        "coefficients": logreg.coef_[0].tolist(),
        "intercept": float(logreg.intercept_[0]),
        "positive_class": "sustained",
        "trained_on": {"analysis": "a", "n": int(len(df)),
                       "n_sustained": int(y.sum()), "n_spike": int(len(y) - y.sum())},
        "rules": {
            "early_weeks": EARLY_WEEKS,
            "onset_multiplier": series.ONSET_MULTIPLIER,
            "onset_confirm_weeks": series.ONSET_CONFIRM_WEEKS,
            "baseline_weeks": series.BASELINE_WEEKS,
            "min_weekly_views": series.MIN_WEEKLY_VIEWS,
        },
    }
    (HERE / "model.json").write_text(json.dumps(payload, indent=2) + "\n")
    print(f"\nWrote model.json (trained on n={len(df)}).")


if __name__ == "__main__":
    main()
