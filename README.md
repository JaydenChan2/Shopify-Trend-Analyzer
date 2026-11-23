# Spike or Stay

**Given an abrupt surge in public interest, will it last?**

A Shopify app (v0) that cross-references a store's products with public interest
data (Wikipedia pageviews) and labels each product's trend as **likely sustained**
or **likely spike**. Each label comes with a confidence and a plain-English reason,
not just a verdict.

**Live demo:** https://spike-or-stay-ecsk.onrender.com, connected to a Shopify dev
store of trend products. Today's view is mostly quiet (none of them is surging this
week), so try a replay, which reruns the app as if it were that date. Each replayed
call now shows **hindsight**: whether it came true, checked on the year that followed.

| Replay | What it shows | Hindsight |
|---|---|---|
| [Pop Mart, 2024-12-08](https://spike-or-stay-ecsk.onrender.com/dashboard?as_of=2024-12-08) | Pop Mart: *Likely sustained*. Labubu: surge, too early to tell | Came true. **Not in the training data**, so a fair test |
| [Labubu, 2025-01-05](https://spike-or-stay-ecsk.onrender.com/dashboard?as_of=2025-01-05) | Labubu: *Likely sustained*. Dubai chocolate and Jellycat: surge, too early to tell | Came true, but Labubu was in the training data |
| [Fidget spinner, 2017-06-12](https://spike-or-stay-ecsk.onrender.com/dashboard?as_of=2017-06-12) | Fidget spinner: *Likely spike* | Came true (in the training data) |
| [Air fryer, 2017-12-31](https://spike-or-stay-ecsk.onrender.com/dashboard?as_of=2017-12-31) | Air fryer: *Likely sustained* | Came true (in the training data) |

[**Discover**](https://spike-or-stay-ecsk.onrender.com/discover) finds surging products
without a store: try [the fidget spinner week](https://spike-or-stay-ecsk.onrender.com/discover?as_of=2017-06-12),
where it picks out the fidget spinner from Wikipedia's 1,000 most-read articles on its own.

It's on Render's free plan, so the first visit after a quiet spell can take up to a minute to wake up.

The model behind the labels was backtested first, on past trends with an
objective labelling rule. The results are below, with the sample size stated.
In short: the model beats both baselines on every analysis, but **n = 16** is
small, so the evidence is promising, not conclusive.

> Scope: the app only detects *abrupt* surges (a 3x jump that holds for two
> weeks). Gradual trends never trigger that, so they show as "No surge detected".
> They aren't covered by v0.

| Fad: fidget spinner, `?as_of=2017-06-12` | Lasting: air fryer, `?as_of=2017-12-31` |
|---|---|
| ![Replay on 2017-06-12: fidget spinner labelled Likely spike](docs/replay-2017-06-12-fidget-spinner.png) | ![Replay on 2017-12-31: air fryer labelled Likely sustained](docs/replay-2017-12-31-air-fryer.png) |

*Replays of trends the model was trained on (in-sample), so they show the pipeline, not accuracy.*

---

## What a merchant sees

| Route | Page |
|---|---|
| `/` | **Landing page.** What it does, how it works in three steps, feature tour, "honest by design", FAQ. Static, so it loads instantly with no API calls. |
| `/dashboard` | **The app**: the product cards described below. |
| `/discover` | **Discover**: products surging on Wikipedia this week, store or not, with the same checks (see below). |
| `/how-it-works` | **Methodology**: the onset and label rules, features, the full backtest table with confidence intervals, and limitations. |
| `/trend?article=…` | One product's trend panel, as a standalone page (the dashboard opens the same panel in a dialog). |

The dashboard, top to bottom:

- **Summary cards** (surges, quiet, not enough data, not mapped). They double as
  **filters**: click one to show only those products.
- **One card per product**, or per group of products sharing an article. Each
  card shows:
  - a label with its confidence ("Likely sustained · 67%")
  - a **sparkline** of the last 26 weeks
  - the reason and any warnings
  - the mapped term and article
  - a *Fix mapping* form
- **Hindsight, on replays.** Each card shows whether its call came true, using the
  backtest's own label rule on the year after the jump (data the call never saw),
  and the banner tallies it ("1 of 1 call came true"). Trends the model was
  trained on are flagged, and left out of a separate "fair" tally.
- **A trend panel.** Clicking a card opens it:
  - two years of weekly views with a hover tooltip
  - the **3× "usual level" surge bar** and the **2,000/week floor** as reference
    lines
  - the **onset** marked, with the **6 weeks the model reads** shaded
  - for scored products, **how the model decided**: each feature's push toward
    *sustained* or *spike* (the logistic regression's per-feature contribution),
    adding up to the shown probability

The look is futuristic minimal: a near-black canvas with a faint engineering grid
behind the hero, hairline borders, big tight headings, small uppercase mono labels
and mono numbers, and one signal colour per meaning (green = sustained, coral =
spike, amber = too early), with a soft glow on chart lines. The landing page's
Fig. 1 is real data (fidget spinner vs air fryer, from the backtest's parity
fixture in `web/db/landing_figure.json`), not a mock-up. Fonts are system fonts, so
the Content-Security-Policy stays `'self'`. The charts are SVG built in Ruby
(`TrendChart`), and interactivity is one small plain-JS file
(`web/app/assets/javascripts/app.js`). There's no front-end framework or build step.

**Dark by default.** The sun/moon button in the nav switches to light mode, and
the choice is remembered in the browser. A tiny script in the page head applies a
saved choice before the page draws, so there's no flash.

Everything works without JavaScript too: each card links to a standalone
`/trend` page with the same panel.

| Label | Meaning |
|---|---|
| **Likely sustained** / **Likely spike** | A surge started 6–10 weeks ago. Scored by the model; confidence is the model's probability for the label. |
| **Surge detected – too early to tell** | Surge confirmed, but there aren't 6 full weeks of data yet. |
| **Possible surge (unconfirmed)** | Only the latest week jumped; a second week is needed to confirm. |
| **No surge detected** | No surge started in the last 10 weeks. |
| **Not enough data** | No views, the article didn't exist yet, or traffic is below 2,000/week. |
| **Not mapped** | No trustworthy Wikipedia article for this product (see limitations). |

Example reason: *"Interest 5.8x its usual level over 6 weeks, holding steady."*

**Replay mode.** Add `?as_of=YYYY-MM-DD` to see what the app would have said on a
past date, e.g. `/dashboard?as_of=2017-06-12` (fidget spinners → *Likely spike*) or
`/dashboard?as_of=2017-12-31` (air fryers → *Likely sustained*). Every series is cut to
complete weeks before that date, so no later data can leak in, and a test proves
it. These trends were in the training data, so replays demo the pipeline; they
don't prove accuracy.

---

## Repo layout

```
backtest/   Python: data, onset/label rules, features, models, results, model.json
web/        Rails 8 app: Shopify + Wikipedia clients, Ruby port of the model, the page
.env        (gitignored) credentials shared by both parts; see .env.example
```

## How to run

### Setup

Copy `.env.example` to `.env` at the repo root. `WIKI_CONTACT` (an email or URL)
is required by Wikimedia for API access. The Shopify variables are optional.

### Backtest (Python 3.12)

```bash
cd backtest
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt           # all versions pinned
export WIKI_CONTACT=you@example.com       # only needed if the cache is missing

pytest                                    # onset/label rules + no-lookahead test
python step_b_onsets.py                   # onsets and labels for every trend
python backtest.py                        # features, LOO-CV, results/, model.json
python export_fixture.py                  # parity fixture for the Rails test
```

Raw API responses are committed in `backtest/cache/`, so the numbers reproduce
without any network calls.

### Web app (Ruby 3.4, Rails 8.1)

```bash
cd web
bundle install
bin/rails server      # http://localhost:3000 (landing page; the app is at /dashboard)
bin/rails db:prepare  # creates the SQLite database (mapping overrides)
bin/rails test        # 185 tests, incl. Python↔Ruby parity and as_of no-lookahead
node script/check_layout.mjs   # with the server running: no horizontal scroll at 320/375/414px,
                               # no console errors or CSP violations (uses your local Chrome)
```

Without Shopify credentials the app runs in **demo mode** with sample products.
To use a real store:

1. In the Shopify Dev Dashboard, create an app in the same organization as your
   dev store, with the `read_products` scope.
2. Release a version and install it on the dev store.
3. Put `SHOPIFY_SHOP_DOMAIN`, `SHOPIFY_CLIENT_ID` and `SHOPIFY_CLIENT_SECRET` in `.env`.

The app gets an Admin API token with the **client credentials grant**. The token
expires after about 24 hours, so it's cached with its expiry and refetched shortly
before it lapses. The app then reads ACTIVE products (title, productType, tags)
through the GraphQL Admin API. There's no OAuth install flow; it isn't needed for
an app and store in the same organization.

### Deploy to Render (public demo)

The repo has a `Dockerfile` (built from the repo root, since the app reads
`backtest/model.json` and `backtest/trends.csv`) and a `render.yaml` Blueprint.

1. Push the repo to GitHub.
2. In Render: **New → Blueprint**, pick the repo. Render reads `render.yaml`.
3. When asked, fill in:
   - `WIKI_CONTACT`: an email or URL (required by Wikipedia).
   - `OVERRIDES_PASSWORD`: optional (see below).

   `SECRET_KEY_BASE` is generated for you, so no `master.key` is needed.
4. Deploy. The first build takes a few minutes; the container runs
   `bin/rails db:prepare` before starting the server.

How the public deploy behaves:

- **Store or demo.** With no Shopify variables, visitors see the sample products.
  To show a store, add `SHOPIFY_SHOP_DOMAIN`, `SHOPIFY_CLIENT_ID` and
  `SHOPIFY_CLIENT_SECRET` in the service's Environment tab. The live demo does
  this with a dev store of trend products. Anyone with the link sees that store's
  product names (the app only reads products), so use a dev store, not a real one.
- **Demo mode (`DEMO_MODE=true`, set in `render.yaml`).** Visitors can use
  *Fix mapping*, *Don't track* and *Remove override*, but their changes are kept in
  their own session cookie, layered on top of the shared seeded overrides
  (`web/db/seeds.rb`), so nobody can change what other visitors see. The header
  shows "Demo store" instead of the shop domain.
- **Without demo mode**, overrides are saved for everyone. In production that's
  locked unless `OVERRIDES_PASSWORD` is set; if it is, saving asks for a username
  (`admin`, or `OVERRIDES_USER`) and that password.
- **Fast first load.** `/dashboard` and `/discover` send the page at once and load
  the cards after (with a loading state; `?inline=1` renders everything in one go,
  which is also the no-JS fallback). When the server boots, a background thread
  warms the cache for the store (today and the replays above) and Discover
  (`CacheWarmer`; `WARM_CACHE=0` turns it off). Measured locally on an empty cache:
  the page shell arrives in ~15 ms either way; the cards took 8.3 s cold and 0.3 s
  once warmed (warming takes ~50 s after boot).
- **Keep-alive.** `.github/workflows/keep-alive.yml` requests `/up` every 10 minutes
  so the free instance doesn't sleep (and its warm cache survives). One service awake
  all month uses ~720-744 of Render's 750 free hours, so it only fits if it's your
  only free service. GitHub pauses schedules after 60 days without commits.
- **Free plan limits.** The service sleeps after about 15 minutes idle, and the
  first visit afterwards takes up to a minute. Storage is wiped on every deploy
  and restart: the Wikipedia cache rebuilds itself, but overrides saved in the UI
  are lost. Overrides for the demo store live in `web/db/seeds.rb`, which runs
  whenever the database is created, so those come back. To keep UI ones, move to a paid instance, attach a disk (e.g. at `/data`) and set
  `DATABASE_PATH=/data/production.sqlite3` and `CACHE_DIR=/data/cache`.

---

## How it works

### 1. Interest data

Wikipedia pageviews (en.wikipedia, all-access, agent=user, daily from 2015-07-01),
summed into Monday–Sunday weeks.

### 2. Onset: when did the surge start?

The onset is the first week where views are **> 3x the median of the previous 26
weeks**, **≥ 2,000/week**, and both conditions **hold for 2 consecutive weeks**.
Both weeks are judged against the baseline before the first one.

Articles created mid-trend have no history to compare against. For them, the
onset is the first time they reach the 2,000/week floor for two weeks in a row,
during their first 26 weeks.

### 3. Label: was it sustained? (objective rule, no hand labelling)

- **Sustained** if mean weekly views in weeks 26–51 after onset are **≥ 25% of the
  peak week** in weeks 0–25.
- **Spike** otherwise.
- Trends without 52 weeks of post-onset data are dropped.

### 4. Features: weeks 0–5 after onset only (no lookahead)

| Feature | Definition (v0..v5 = weekly views) |
|---|---|
| growth | ln((mean(v3..v5)+1) / (mean(v0..v2)+1)) |
| acceleration | ln((v5+1)/(v3+1)) − ln((v2+1)/(v0+1)) |
| peak_sharpness | max / mean of the 6 weeks |
| volatility | std of the 5 week-over-week log changes |
| yoy_ratio | vs. the same 6 weeks a year earlier (*shown, not used in v0*) |

A test tampers with every week after week 5 and checks that the features don't change.

### 5. Model

Logistic regression on the 4 standardized features (scikit-learn defaults). It's
exported to `backtest/model.json` as weights, intercept and scaling. The Rails app
applies the same formula in plain Ruby, with no Python at runtime.

A parity test runs 16 cases (9 real trends, 7 edge cases) through both languages.
They must agree on onset, features and probability to within 1e-9.

### 6. Live labels

For each product:

1. The search term is its productType, falling back to its title.
2. The term is mapped to a Wikipedia article via search, then sanity-checked.
3. Weekly views come from Rails.cache or the API.
4. The app looks for an onset in the last 10 complete weeks and assigns one of the labels above.

Products mapping to the same article are grouped into one row with a count.

### 7. Hindsight (replays)

On a replay, every call with a surge is checked against what happened next, using
the backtest's label rule on the following year: sustained if weeks 26–51 after the
onset average at least 25% of the peak week in weeks 0–25 (`Hindsight`; a parity
test checks the Ruby rule against Python's `label_from_onset`).

- **Came true / Missed** for *Likely sustained/spike* calls; *What happened* for
  surges that were still too early to call.
- **Too recent to check** until a full year of complete weeks exists.
- **Can't check** when the article was merged into another before the year was up.
- **Trained on this trend** when it's one of the 16 the model was fitted on. Those
  checks aren't a fair test, and the banner reports a separate tally without them.

The answer key reads data after `as_of`; the call itself never does.

### 8. Discover

`/discover` finds products without a store (`TrendingProducts`):

1. **Candidates.** The 1,000 most-read English Wikipedia articles on each day of
   the last complete week, summed. Only days up to the replay's last complete week
   are read (tested).
2. **Products only.** Wikidata says what each one is: an article is kept if its
   type falls under toy, food, drink, clothing, cosmetics, home appliance,
   electronics, tabletop game or brand, and not under software, video game, film,
   media franchise or weapon (medication only if it isn't also food or drink).
   "Game" and "product model" were tried and dropped: they pulled in the Premier
   League, Formula One, bombers and missiles.
3. **Same checks** as store products: live label, sparkline, trend panel and, on
   replays, hindsight. Cards with a surge in the last 10 weeks are shown; the rest
   are listed as "popular, no jump".

Walking Wikidata's "subclass of" graph is slow (SPARQL property paths took 2–100s
and sometimes failed), so the app climbs it one level at a time with simple
lookups, caches each type's parents, and ships a snapshot of the graph
(`web/db/wikidata_parents.json`, ~5,500 types). A cold scan takes about 9 seconds;
a cached one is instant. Refresh the snapshot with `bin/rails discover:catalog`.

On the 2017-06-12 replay, Discover finds the fidget spinner on its own and calls
it a *Likely spike*. It also flags early, unconfirmed jumps in M&M's, Trader Joe's
and jalebi, all of which faded.

---

## Backtest results

### Process

32 candidate trends were listed **before** looking at any data: 14 likely fads and
18 likely sustained, all post-mid-2015, sellable consumer products or foods, not
COVID-driven. Each Wikipedia article's history was audited for redirects, renames
and merges (`audit_titles.py`). Rejected candidates and the reasons are in
`candidates_rejected.csv`.

Thresholds, features, models and the analyses to report were pre-registered in
[`backtest/PREREGISTRATION.md`](backtest/PREREGISTRATION.md) before any results.
Two amendments are recorded there, with reasons:

1. **The 2-week confirmation.** This was added after seeing onsets, because 7
   onsets were one-day Main Page or news blips. It was decided before any model
   results, and the original rule is still reported as analysis (d).
2. **Wilson confidence intervals.** Reporting only.

### Results (leave-one-out cross-validation)

| Analysis | n (sust. / spike) | Majority | Naive: "still rising in week 6" | **Logistic regression** |
|---|---|---|---|---|
| **(a) Primary** | **16** (8 / 8) | 0/16 = 0.00 | 10/16 = 0.62 [0.39–0.82] | **12/16 = 0.75 [0.51–0.90]** |
| (b) Excl. articles created mid-trend | 6 (2 / 4) | 0.67 | 0.50 | 0.83 [0.44–0.97], *too small to interpret* |
| (c) Robustness: 2x multiplier | 25 (18 / 7) | 0.72 | 0.52 | 0.88 [0.70–0.96] |
| (d) Original 1-week rule | 23 (13 / 10) | 0.57 | 0.57 | 0.65 [0.45–0.81] |

Brackets are Wilson 95% confidence intervals. Full tables, precision/recall,
confusion matrices and per-trend predictions are in
[`backtest/results/step_d_results.md`](backtest/results/step_d_results.md).

### How to read this

- **Logistic regression beats both baselines on accuracy in all four analyses.**
- **The margin over the naive baseline in (a) is 2 trends** (12 vs 10 of 16). An
  exact McNemar test (exploratory, not pre-registered) gives p = 0.69. At this
  sample size we can't tell them apart.
- The majority baseline's 0/16 is a leave-one-out artifact on balanced data:
  removing a trend always makes its own class the minority. Chance is 50%.
- (c) has the strongest result (vs naive p = 0.02, exploratory). (b) has only 6
  trends, so it says nothing either way.
- The learned weights make sense: **sharp early peaks** (−1.20, standardized) and
  **jumpy weeks** (−0.88) point to *spike*; **growth** (+0.35) points to *sustained*.
- **Misses in (a):** Fidget spinner, Stanley tumbler and Choker were called
  *sustained* but were spikes. Dubai chocolate was the reverse. Fidget spinner is
  the instructive one: at week 6 it was still climbing smoothly, and six weeks
  isn't enough to tell a fad that's still rising from a trend that will last.

---

## Known limitations

**Small dataset.** n = 16 labelled trends in the primary analysis. 16 of 32
candidates were dropped because the onset rule never fired. Treat the accuracy
as a signal, not a guarantee.

**Only abrupt surges.**
- Old, popular articles with gradual growth never show a 3x jump. Examples:
  keto diet, matcha, pickleball, Hoka. 11 of the 16 dropped trends were
  likely-sustained ones.
- So the model answers "given an abrupt surge, will it last?". Gradual trends
  show as "No surge detected".

**Wikipedia is a proxy for interest, not demand.**
- Readers aren't buyers.
- Articles about a brand or company dilute product interest (Impossible Foods,
  Stanley, Hoka).
- Main Page features and news events cause one-day spikes. The 2-week rule
  filters most of them, not all: Scrunchie's onset is still dominated by one day.

**Articles created mid-trend.** 11 of 32 candidates had no pre-trend history.
Their onset is when the article appeared, which is often near the peak. That
biases the first 6 weeks (e.g. Instant Pot is labelled *spike*). Analysis (b)
excludes them, but leaves only 6 trends.

**Seasonality.**
- 8 of the 16 primary onsets fall in November or December (9 of 23 under the
  original 1-week rule).
- A holiday peak can trigger the onset and inflate the peak the label is measured
  against. Air fryer's onset is the 2017 Black Friday ramp.
- Only year-over-year is computed, and it isn't used in the model.

**Product → article mapping is the weakest link.**
- **"The Minimal Snowboard"** (title fallback) searched to **"1080° Snowboarding"**,
  a video game. A sanity check now rejects results whose title words aren't in the
  search term, so it shows as *Not mapped*. But a check like this can't catch
  every bad match.
- **Air fryer** now redirects to **Convection oven**, a broader article with no
  air fryer surge. The row shows a warning. Replays before the 2023 merge use the
  old article's own views (cutoff from `backtest/trends.csv`).
- Live lookups don't sum former titles, unlike the backtest. A replay of Stanley
  in 2017 finds no views because the article was called "Stanley bottle" then.
- Generic product types (accessories, giftcard, …) are deliberately *Not mapped*.
- **Fixable per term:** every row has a *Fix mapping* form. A merchant can point
  the search term at a specific Wikipedia article (checked to exist, and saved
  under its real title if it's a redirect) or mark it *Don't track*. Overrides are
  stored in SQLite (`mapping_overrides`) and apply to every product with that term.
  Auto-mapping still gets things wrong, but a wrong mapping is now a one-click fix.

**No store data yet.** There's no sales velocity, inventory or order data.
Labels describe public interest, not this store's demand.

**v0 shortcuts.**
- Only the first 50 active products are read (pagination TODO).
- The Shopify token is cached in plain text under `web/tmp/` (gitignored), which
  is fine for a dev store, not for production.
- Replays use today's Wikipedia search results to map products.
- Discover only sees articles in Wikipedia's daily top 1,000 (roughly 10,000+
  views a day), so it misses smaller surges a store could still care about. Its
  product filter is a heuristic on Wikidata's types: expect some odd entries
  (an Anglo-Saxon helmet once counted as clothing), and some products missed.
- No user accounts. Locally, anyone who can open the app can edit mapping
  overrides. In production they're locked, or behind one shared password
  (`OVERRIDES_PASSWORD`), which is enough for a demo but isn't per-merchant access.

---

## Next steps

- **Sales tie-in:** order webhooks and sales velocity, so labels can be checked
  against what the store actually sells.
- **Seasonality:** compare against the same weeks last year, and add YoY to the
  model with a `has_prior_year` flag (missing for new articles).
- **Mapping:** stitch former titles in live lookups, and suggest candidate
  articles in the *Fix mapping* form instead of requiring an exact title.
- **More data:** a second interest source (e.g. Google Trends) and more labelled
  trends. More trends is the main thing needed to make the accuracy estimate meaningful.
- **Gradual trends:** a separate detector for slow, steady growth.
- **Product:** embed in Shopify admin (App Bridge + session tokens). Inside the
  admin, Shopify expects the Polaris look, so the embedded view would switch to
  Polaris components. Also weekly digest emails and an OAuth install flow for a
  public app.
