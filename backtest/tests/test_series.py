"""Onset and label rules on synthetic series (no network)."""
import pandas as pd

from series import detect_onset, label_from_onset


def weekly(values):
    return pd.Series(values, index=pd.date_range("2016-01-03", periods=len(values), freq="W-SUN"))


def test_ratio_onset_needs_both_multiplier_and_floor():
    # 26 weeks at 1000, then 2500 (2.5x: no), then 3500 (3.5x and >= 2000: yes)
    s = weekly([1000] * 26 + [2500, 3500, 3500])
    assert detect_onset(s) == (27, "ratio")


def test_one_week_blip_is_not_onset_with_two_week_confirmation():
    s = weekly([1000] * 26 + [20000, 1200, 1100] + [1000] * 5)
    assert detect_onset(s) == (None, None)
    assert detect_onset(s, confirm_weeks=1) == (26, "ratio")  # the original rule would fire


def test_two_week_confirmation_uses_baseline_before_onset_week():
    # week 27 is 3.5x the pre-week-26 baseline, so the surge is confirmed at 26
    s = weekly([1000] * 26 + [5000, 3500, 1000])
    assert detect_onset(s) == (26, "ratio")


def test_small_article_tripling_below_floor_is_not_onset():
    s = weekly([100] * 26 + [400, 500, 600])
    assert detect_onset(s) == (None, None)


def test_fallback_for_article_created_mid_trend():
    # zeros = article didn't exist yet; then it appears already popular
    s = weekly([0] * 30 + [500, 5000, 8000])
    assert detect_onset(s) == (31, "fallback")


def test_fallback_also_needs_two_weeks_above_floor():
    s = weekly([0] * 30 + [500, 5000, 900, 800, 3000, 3000])
    assert detect_onset(s) == (34, "fallback")


def test_article_existing_at_data_start_never_uses_fallback():
    # big from week 0 (evergreen) -> its first weeks are baseline, not an onset
    s = weekly([5000] * 40)
    assert detect_onset(s) == (None, None)


def test_label_sustained_vs_spike():
    peak_then_hold = weekly([10000] * 26 + [3000] * 26)   # 30% of peak
    peak_then_fade = weekly([10000] * 26 + [2000] * 26)   # 20% of peak
    assert label_from_onset(peak_then_hold, 0)[0] == "sustained"
    assert label_from_onset(peak_then_fade, 0)[0] == "spike"


def test_label_requires_52_weeks():
    assert label_from_onset(weekly([10000] * 51), 0)[0] is None
