"""Step B: onset + label for every trend. No features, no model.

Usage: python step_b_onsets.py [confirm_weeks]   (default: series.ONSET_CONFIRM_WEEKS)
Writes results/step_b_onsets_{N}week.csv and prints a table.
"""
import sys
from collections import Counter
from pathlib import Path

import pandas as pd

from series import ONSET_CONFIRM_WEEKS, detect_onset, label_from_onset, load_trends, weekly_series

RESULTS_DIR = Path(__file__).parent / "results"


def main():
    confirm_weeks = int(sys.argv[1]) if len(sys.argv) > 1 else ONSET_CONFIRM_WEEKS
    rows = []
    for trend in load_trends():
        weekly = weekly_series(trend)
        onset, rule = detect_onset(weekly, confirm_weeks=confirm_weeks)
        row = {"name": trend["name"], "likely_type": trend["likely_type"],
               "created_mid_trend": trend["created_mid_trend"]}
        if onset is None:
            row.update(status="DROPPED", reason="no onset detected")
        else:
            week_end = weekly.index[onset]
            label, peak, late = label_from_onset(weekly, onset)
            row.update(onset_week=(week_end - pd.Timedelta(days=6)).date(), rule=rule,
                       onset_views=int(weekly.iloc[onset]),
                       q4_onset="yes" if week_end.month in (11, 12) else "")
            if label is None:
                weeks_after = len(weekly) - onset
                row.update(status="DROPPED", reason=f"only {weeks_after} weeks after onset (need 52)")
            else:
                row.update(status="kept", label=label, peak=int(peak), late_mean=int(late),
                           late_over_peak=round(late / peak, 3))
        rows.append(row)

    df = pd.DataFrame(rows)
    RESULTS_DIR.mkdir(exist_ok=True)
    df.to_csv(RESULTS_DIR / f"step_b_onsets_{confirm_weeks}week.csv", index=False)

    pd.set_option("display.width", 250, "display.max_columns", 20)
    print(df.fillna("").to_string(index=False))

    kept = df[df.status == "kept"]
    dropped = df[df.status == "DROPPED"]
    print(f"\nKept {len(kept)} / {len(df)}.  Labels: {dict(Counter(kept.label))}")
    print(f"Dropped by likely_type: {dict(Counter(dropped.likely_type))}")
    print(f"Kept by likely_type:    {dict(Counter(kept.likely_type))}")
    print(f"Onset rule vs created_mid_trend flag:\n{pd.crosstab(df.created_mid_trend, df.rule.fillna('none'))}")


if __name__ == "__main__":
    main()
