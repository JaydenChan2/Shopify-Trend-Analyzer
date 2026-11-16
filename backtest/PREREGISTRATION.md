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

---

## Amendment 1: two-week onset confirmation (added AFTER seeing Step B)

**Status:** made after Step B onsets and labels were inspected, before any
feature or model result existed. Not part of the original pre-registration.

**What we saw:** in 7 of 23 onsets a single day carried 31–93% of the onset
week's views and the next week fell back (Liquid Death, Pickleball, Rolled ice
cream, Slime, Scrunchie, Impossible Foods, CBD). Those onsets reflect a Main Page
feature or news hit, not the start of a trend, so their labels measured the size
of the blip.

**Reasoning (recorded by the project owner before the rerun):** single-day
attention from Main Page features or news hits isn't a trend start, and requiring
the surge to hold a second week filters that out without lookahead past the
feature window.

**Change:** `ONSET_CONFIRM_WEEKS = 2`. The onset condition (ratio rule or
fallback) must hold in weeks t and t+1, both compared against the baseline before
week t. Onset is week t. The live app uses the same rule.

**Reporting:** Step D reports a fourth line, **(d)**, the original 1-week rule
on all rows, so the effect of this amendment is visible.

---

## Amendment 2: Wilson confidence intervals (reporting only, added before Step D)

**Status:** added after Step B, before any feature or model result existed. It
changes reporting only: no data, rule, feature or model choice.

- Every accuracy is reported with a Wilson 95% confidence interval (z = 1.96).
- Clarification of an unspecified detail: if a training fold's labels are tied,
  the majority baseline predicts "spike".
- Known label noise, accepted with no further rule changes: Scrunchie (onset
  dominated by a single day), Impossible Foods (onset week is its news peak),
  Mom jeans (onset in Christmas week).
- Analysis (b) has n = 6 and is reported but marked too small to interpret.
