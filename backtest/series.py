"""Weekly series, onset detection and the objective sustained/spike label.

All thresholds are pre-registered in PREREGISTRATION.md. Don't tune them.
"""
import csv
from pathlib import Path

import numpy as np
import pandas as pd

import wiki

ONSET_MULTIPLIER = 3.0    # onset week must exceed this x the baseline median...
BASELINE_WEEKS = 26       # ...of this many previous weeks
MIN_WEEKLY_VIEWS = 2000   # ...and clear this absolute floor
ONSET_CONFIRM_WEEKS = 2   # ...for this many consecutive weeks (amendment 1, see PREREGISTRATION.md)
LABEL_PEAK_WEEKS = 26     # peak taken over weeks 0..25 after onset
LABEL_LATE_END = 52       # late mean over weeks 26..51 after onset
SUSTAIN_RATIO = 0.25      # sustained if late mean >= this x peak

FIRST_MONDAY = "2015-07-06"  # data starts Wed 2015-07-01; drop that partial week
TRENDS_CSV = Path(__file__).parent / "trends.csv"


def load_trends():
    with open(TRENDS_CSV, newline="") as f:
        return list(csv.DictReader(f))


def weekly_series(trend):
    """Daily views summed over the article + its former titles -> Mon-Sun weekly totals."""
    days = pd.date_range(FIRST_MONDAY, pd.Timestamp(wiki.END_DATE))
    daily = pd.Series(0, index=days, dtype="int64")
    titles = [trend["article"]] + [t for t in trend["former_titles"].split(";") if t]
    for title in titles:
        for item in wiki.fetch_daily_pageviews(title):
            day = pd.Timestamp(item["timestamp"][:8])
            if day in daily.index:
                daily[day] += item["views"]
    if trend["valid_until"]:
        daily = daily[: pd.Timestamp(trend["valid_until"])]
        # keep only complete weeks: cut back to the last Sunday
        daily = daily[: daily.index[daily.index.dayofweek == 6][-1]]
    return daily.resample("W-SUN").sum()  # index = week-ending Sunday


def detect_onset(weekly, multiplier=ONSET_MULTIPLIER, confirm_weeks=ONSET_CONFIRM_WEEKS):
    """Return (onset_index, rule) or (None, None).

    rule is "ratio" (beat multiplier x median of the 26 weeks before the onset
    week) or "fallback" (article created after data start; first week >= floor
    during its first 26 weeks of existence).

    The condition must hold for `confirm_weeks` consecutive weeks starting at the
    onset week, all compared against the SAME baseline (the one before week t),
    so a one-week blip from a Main Page feature or news hit isn't an onset.
    """
    values = weekly.to_numpy()
    nonzero = np.flatnonzero(values > 0)
    if len(nonzero) == 0:
        return None, None
    first_week = nonzero[0]
    created_after_start = first_week > 0

    for t in range(len(values) - confirm_weeks + 1):
        window = values[t:t + confirm_weeks]
        weeks_of_history = t - first_week
        if weeks_of_history >= BASELINE_WEEKS:
            baseline = np.median(values[t - BASELINE_WEEKS:t])
            if all(window > multiplier * baseline) and all(window >= MIN_WEEKLY_VIEWS):
                return t, "ratio"
        elif created_after_start and weeks_of_history >= 0:
            if all(window >= MIN_WEEKLY_VIEWS):
                return t, "fallback"
    return None, None


def label_from_onset(weekly, onset):
    """Return (label, peak, late_mean) or (None, ...) if there isn't 52 weeks of data."""
    values = weekly.to_numpy()
    if onset + LABEL_LATE_END > len(values):
        return None, None, None
    peak = values[onset:onset + LABEL_PEAK_WEEKS].max()
    late_mean = values[onset + LABEL_PEAK_WEEKS:onset + LABEL_LATE_END].mean()
    label = "sustained" if late_mean >= SUSTAIN_RATIO * peak else "spike"
    return label, peak, late_mean
