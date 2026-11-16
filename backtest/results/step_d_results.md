# Step D results

Leave-one-out CV. Confusion matrix rows = actual [sustained, spike], columns = predicted [sustained, spike]. Precision is n/a when a class was never predicted.

## (a) Primary: all rows (3x, 2-week confirm)

n = 16 trends (8 sustained, 8 spike)

| Model | Accuracy (k/n) | 95% CI | Prec sust. | Rec sust. | Prec spike | Rec spike | Confusion [[SS,SP],[PS,PP]] |
|---|---|---|---|---|---|---|---|
| majority | 0.00 (0/16) | 0.00–0.19 | 0.00 | 0.00 | 0.00 | 0.00 | [[0, 8], [8, 0]] |
| naive | 0.62 (10/16) | 0.39–0.82 | 0.62 | 0.62 | 0.62 | 0.62 | [[5, 3], [3, 5]] |
| logreg | 0.75 (12/16) | 0.51–0.90 | 0.70 | 0.88 | 0.83 | 0.62 | [[7, 1], [3, 5]] |

## (b) Excluding created_mid_trend rows (3x, 2-week)

n = 6 trends (2 sustained, 4 spike)  **— too small to interpret (amendment 2)**

| Model | Accuracy (k/n) | 95% CI | Prec sust. | Rec sust. | Prec spike | Rec spike | Confusion [[SS,SP],[PS,PP]] |
|---|---|---|---|---|---|---|---|
| majority | 0.67 (4/6) | 0.30–0.90 | n/a | 0.00 | 0.67 | 1.00 | [[0, 2], [0, 4]] |
| naive | 0.50 (3/6) | 0.19–0.81 | 0.33 | 0.50 | 0.67 | 0.50 | [[1, 1], [2, 2]] |
| logreg | 0.83 (5/6) | 0.44–0.97 | 1.00 | 0.50 | 0.80 | 1.00 | [[1, 1], [0, 4]] |

## (c) Robustness: 2x multiplier (2-week confirm)

n = 25 trends (18 sustained, 7 spike)

| Model | Accuracy (k/n) | 95% CI | Prec sust. | Rec sust. | Prec spike | Rec spike | Confusion [[SS,SP],[PS,PP]] |
|---|---|---|---|---|---|---|---|
| majority | 0.72 (18/25) | 0.52–0.86 | 0.72 | 1.00 | n/a | 0.00 | [[18, 0], [7, 0]] |
| naive | 0.52 (13/25) | 0.33–0.70 | 0.88 | 0.39 | 0.35 | 0.86 | [[7, 11], [1, 6]] |
| logreg | 0.88 (22/25) | 0.70–0.96 | 0.86 | 1.00 | 1.00 | 0.57 | [[18, 0], [3, 4]] |

## (d) Original 1-week rule (3x, pre-amendment)

n = 23 trends (13 sustained, 10 spike)

| Model | Accuracy (k/n) | 95% CI | Prec sust. | Rec sust. | Prec spike | Rec spike | Confusion [[SS,SP],[PS,PP]] |
|---|---|---|---|---|---|---|---|
| majority | 0.57 (13/23) | 0.37–0.74 | 0.57 | 1.00 | n/a | 0.00 | [[13, 0], [10, 0]] |
| naive | 0.57 (13/23) | 0.37–0.74 | 0.64 | 0.54 | 0.50 | 0.60 | [[7, 6], [4, 6]] |
| logreg | 0.65 (15/23) | 0.45–0.81 | 0.65 | 0.85 | 0.67 | 0.40 | [[11, 2], [6, 4]] |

## Per-trend predictions, analysis (a)

| name | onset_week | label | majority | naive | logreg | logreg_prob_sustained | growth | acceleration | peak_sharpness | volatility | yoy_ratio |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Fidget spinner | 2017-04-10 | spike | sustained | sustained | sustained | 0.683 | 1.876 | -1.726 | 2.314 | 0.428 |  |
| Hatchimals | 2016-12-05 | spike | sustained | spike | spike | 0.327 | -0.496 | -2.468 | 1.53 | 0.642 |  |
| Snap Spectacles | 2017-01-30 | spike | sustained | spike | spike | 0.036 | 0.722 | 0.857 | 2.467 | 0.766 |  |
| Scrunchie | 2019-01-28 | spike | sustained | spike | spike | 0.0 | -1.284 | 2.077 | 3.384 | 0.56 | 7.273 |
| Prime (drink) | 2022-11-07 | sustained | spike | sustained | sustained | 0.871 | 0.636 | -0.146 | 1.503 | 0.093 |  |
| Dubai chocolate | 2024-12-16 | sustained | spike | sustained | spike | 0.405 | 0.207 | 1.367 | 1.757 | 0.357 |  |
| Labubu | 2024-11-18 | sustained | spike | sustained | sustained | 0.835 | 0.432 | -0.066 | 1.451 | 0.158 |  |
| Choker | 2016-09-19 | spike | sustained | spike | sustained | 0.652 | -0.374 | 0.749 | 1.76 | 0.284 | 5.05 |
| Mom jeans | 2018-12-24 | sustained | spike | spike | sustained | 0.707 | -0.27 | 0.024 | 1.406 | 0.265 | 3.561 |
| Air fryer | 2017-11-06 | sustained | spike | sustained | sustained | 0.626 | 0.037 | -0.766 | 1.46 | 0.321 | 3.78 |
| Instant Pot | 2017-12-04 | spike | sustained | spike | spike | 0.178 | 1.08 | -3.206 | 1.85 | 0.735 |  |
| Oat milk | 2019-03-25 | sustained | spike | spike | sustained | 0.584 | -0.51 | -0.2 | 1.546 | 0.256 | 24.945 |
| Impossible Foods | 2019-04-29 | spike | sustained | sustained | spike | 0.468 | -0.459 | 0.255 | 1.81 | 0.375 | 14.163 |
| Hard seltzer | 2019-08-12 | sustained | spike | sustained | sustained | 0.557 | 0.452 | -0.09 | 1.466 | 0.418 |  |
| Stanley tumbler | 2023-11-13 | spike | sustained | sustained | sustained | 0.778 | -0.382 | 1.064 | 1.611 | 0.26 | 4.33 |
| Liquid Death | 2021-07-05 | sustained | spike | spike | sustained | 0.753 | 0.161 | -0.654 | 1.314 | 0.287 |  |
