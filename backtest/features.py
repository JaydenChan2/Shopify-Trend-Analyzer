"""Early-window features: ONLY weeks 0..5 after onset (no lookahead).

Formulas are pre-registered in PREREGISTRATION.md. The Ruby port in the Rails
app must match these exactly (checked by the parity test).
"""
import numpy as np

EARLY_WEEKS = 6
MODEL_FEATURES = ["growth", "acceleration", "peak_sharpness", "volatility"]  # yoy excluded in v0


def early_window(values, onset):
    """The only slice of post-onset data any feature may see."""
    window = np.asarray(values[onset:onset + EARLY_WEEKS], dtype=float)
    if len(window) < EARLY_WEEKS:
        raise ValueError("need 6 complete weeks after onset")
    return window


def prior_year_window(values, onset):
    """Same 6 weeks one year earlier (past data, so not lookahead), or None."""
    start = onset - 52
    if start < 0:
        return None
    return np.asarray(values[start:start + EARLY_WEEKS], dtype=float)


def compute_features(values, onset):
    v = early_window(values, onset)
    log_changes = np.log((v[1:] + 1) / (v[:-1] + 1))
    features = {
        "growth": float(np.log((v[3:6].mean() + 1) / (v[0:3].mean() + 1))),
        "acceleration": float(np.log((v[5] + 1) / (v[3] + 1)) - np.log((v[2] + 1) / (v[0] + 1))),
        "peak_sharpness": float(v.max() / v.mean()),
        "volatility": float(log_changes.std()),  # population std (ddof=0); Ruby must match
    }
    prior = prior_year_window(values, onset)
    features["yoy_ratio"] = float(v.mean() / prior.mean()) if prior is not None and prior.mean() > 0 else None
    return features


def still_rising(values, onset):
    """Naive baseline: sustained if week 5 > week 4."""
    v = early_window(values, onset)
    return bool(v[5] > v[4])
