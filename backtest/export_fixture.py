"""Write parity_fixture.json: inputs + Python's outputs for the Ruby parity test.

Each case is a full weekly series. Python computes onset (index + rule),
features, P(sustained) using model.json, and the outcome label (the app's
hindsight check uses the same rule); the Rails test runs the same series
through the Ruby port and must match to 1e-9.

Usage: python export_fixture.py
"""
import json
import math
from pathlib import Path

import numpy as np

import series
from backtest import build_dataset, fit_logreg
from features import EARLY_WEEKS, MODEL_FEATURES, compute_features

HERE = Path(__file__).parent
MODEL = json.loads((HERE / "model.json").read_text())

REAL_TRENDS = ["Fidget spinner", "Hatchimals", "Scrunchie", "Labubu", "Air fryer",
               "Stanley tumbler", "Liquid Death", "Pickleball", "Slime (toy)"]

SYNTHETIC = {
    "one_week_blip": [1000] * 26 + [20000, 1200, 1100] + [1000] * 10,
    "two_week_surge": [1000] * 26 + [5000, 3500, 4000, 4200, 3900, 3000, 2800, 2500],
    "created_mid_trend": [0] * 30 + [500, 5000, 8000, 9000, 7000, 6000, 5000, 4000],
    "fallback_needs_two_weeks": [0] * 30 + [500, 5000, 900, 800, 3000, 3000, 3100, 2900, 2700, 2600],
    "below_floor": [100] * 26 + [400, 500, 600, 700, 800, 900],
    "evergreen_no_onset": [5000] * 60,
    "onset_without_six_weeks": [1000] * 26 + [5000, 5000, 5000],
}


def score(features):
    z = [(features[f] - m) / s for f, m, s in zip(MODEL["features"], MODEL["scaler_mean"], MODEL["scaler_scale"])]
    logit = MODEL["intercept"] + sum(c * zi for c, zi in zip(MODEL["coefficients"], z))
    return 1 / (1 + math.exp(-logit))


def case(name, values):
    values = [int(v) for v in values]
    onset, rule = series.detect_onset(series_from(values))
    out = {"name": name, "values": values, "onset": onset, "rule": rule, "features": None, "probability": None,
           "label": None, "peak": None, "late_mean": None}
    if onset is not None:
        label, peak, late_mean = series.label_from_onset(series_from(values), onset)
        if label is not None:
            out.update(label=label, peak=float(peak), late_mean=float(late_mean))
    if onset is not None and onset + EARLY_WEEKS <= len(values):
        feats = compute_features(np.array(values, dtype=float), onset)
        out["features"] = feats
        out["probability"] = score(feats)
    return out


def series_from(values):
    import pandas as pd
    return pd.Series(values, index=pd.date_range("2015-07-12", periods=len(values), freq="W-SUN"))


def check_formula_matches_sklearn():
    """model.json's formula must reproduce sklearn's predict_proba on the training rows."""
    df = build_dataset(series.ONSET_MULTIPLIER, series.ONSET_CONFIRM_WEEKS, False)
    model = fit_logreg(df[MODEL_FEATURES].to_numpy(), (df["label"] == "sustained").astype(int).to_numpy())
    sk = model.predict_proba(df[MODEL_FEATURES].to_numpy())[:, 1]
    mine = [score(row) for row in df[MODEL_FEATURES].to_dict("records")]
    assert np.allclose(sk, mine, atol=1e-12), "model.json formula disagrees with sklearn"


def main():
    check_formula_matches_sklearn()
    trends = {t["name"]: t for t in series.load_trends()}
    cases = [case(name, series.weekly_series(trends[name]).to_numpy()) for name in REAL_TRENDS]
    cases += [case(name, values) for name, values in SYNTHETIC.items()]
    (HERE / "parity_fixture.json").write_text(json.dumps({"tolerance": 1e-9, "cases": cases}, indent=1) + "\n")
    for c in cases:
        print(f"{c['name']:<26} onset={c['onset']} rule={c['rule']} p={c['probability']} label={c['label']}")


if __name__ == "__main__":
    main()
