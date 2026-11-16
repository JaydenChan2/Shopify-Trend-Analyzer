"""No-lookahead guarantee: features must not change when data after week 5 changes."""
import numpy as np
import pytest

from features import EARLY_WEEKS, compute_features, still_rising

RNG = np.random.default_rng(0)


def series_with_onset(onset=60, length=140):
    return RNG.integers(500, 50000, size=length).astype(float), onset


def test_features_ignore_everything_after_the_early_window():
    values, onset = series_with_onset()
    before = compute_features(values, onset)

    tampered = values.copy()
    tampered[onset + EARLY_WEEKS:] = RNG.integers(0, 10_000_000, size=len(values) - onset - EARLY_WEEKS)
    assert compute_features(tampered, onset) == before
    assert still_rising(tampered, onset) == still_rising(values, onset)


def test_features_work_on_a_series_truncated_right_after_week_5():
    values, onset = series_with_onset()
    truncated = values[:onset + EARLY_WEEKS]
    assert compute_features(truncated, onset) == compute_features(values, onset)


def test_features_refuse_incomplete_window():
    values, onset = series_with_onset()
    with pytest.raises(ValueError):
        compute_features(values[:onset + EARLY_WEEKS - 1], onset)


def test_known_values():
    values = np.array([1000, 2000, 4000, 8000, 8000, 6000], dtype=float)
    f = compute_features(values, 0)
    assert f["growth"] == pytest.approx(np.log(7334.3333333 / 2334.3333333), rel=1e-6)
    assert f["peak_sharpness"] == pytest.approx(8000 / 4833.333333, rel=1e-6)
    assert f["yoy_ratio"] is None
