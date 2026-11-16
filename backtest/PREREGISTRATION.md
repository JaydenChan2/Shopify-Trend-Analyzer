# Backtest pre-registration

Committed together with the trend list, **before** any onset, label, feature or
model result was looked at. Anything changed after this commit must be a separate,
visible commit with a reason.

## Data
- Wikipedia pageviews, en.wikipedia, all-access, agent=user, daily, 2015-07-01 to 2026-11-08.
- Daily views summed across `article` + `former_titles` (renames of the same page only).
- Series cut at `valid_until` when set.
- Weekly = Monday–Sunday sums. First partial week (2015-07-01..05) dropped.

## Onset (constants in `series.py`)
- `ONSET_MULTIPLIER = 3.0`, `BASELINE_WEEKS = 26`, `MIN_WEEKLY_VIEWS = 2000`.
- Onset = first week where views > 3 × median of the previous 26 weeks AND ≥ 2,000.
- Fallback for articles created after data start: during their first 26 weeks of
  existence (first non-zero week), onset = first week ≥ 2,000.
- Articles that existed at data start never use the fallback (their first 26 weeks
  of data are only used as a baseline).

## Label (objective rule)
- `peak` = max weekly views over weeks 0–25 after onset.
- `late` = mean weekly views over weeks 26–51 after onset.
- **sustained** if `late ≥ 0.25 × peak`, else **spike**.
- Dropped if fewer than 52 weeks of data after onset, or no onset detected.

## Features (weeks 0–5 after onset only; v0..v5)
- `growth` = ln((mean(v3..v5)+1) / (mean(v0..v2)+1))
- `acceleration` = ln((v5+1)/(v3+1)) − ln((v2+1)/(v0+1))
- `peak_sharpness` = max(v0..v5) / mean(v0..v5)
- `volatility` = std of the 5 week-over-week log changes ln((v[t]+1)/(v[t-1]+1))
- `yoy_ratio` = mean(v0..v5) / mean(same 6 weeks one year earlier), only if the
  article had views then. **Computed and displayed, not used in the v0 model.**

## Models (leave-one-out CV)
1. Majority class (of the training fold).
2. Naive: sustained if v5 > v4 (still rising in week 6).
3. Logistic regression on the 4 features, StandardScaler fit inside each fold,
   scikit-learn defaults (L2, C=1.0).

Metrics: accuracy, per-class precision/recall, confusion matrix, per-trend predictions.

## Analyses (all three reported, whatever they show)
- **(a) Primary:** all rows that get a label.
- **(b)** Excluding rows with `created_mid_trend = yes` in `trends.csv`.
- **(c)** Robustness: (a) rerun with `ONSET_MULTIPLIER = 2.0` (onsets, labels and
  features all recomputed).

If the logistic regression does not beat both baselines in (a), the README says so plainly.
`model.json` is exported from the model fit on all rows of (a).
