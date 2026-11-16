"""Thin Wikipedia API client with an on-disk cache.

Wikimedia rejects requests without a descriptive User-Agent that includes
contact info, so we build one from the WIKI_CONTACT env var (never hardcoded).
"""
import json
import os
import time
from pathlib import Path

import requests

CACHE_DIR = Path(__file__).parent / "cache"
ACTION_API = "https://en.wikipedia.org/w/api.php"
PAGEVIEWS_API = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user"

# Fixed date range so cached files never go stale and reruns are reproducible.
# Data starts 2015-07-01; END_DATE is the last complete Mon-Sun week before we ran this.
START_DATE = "20150701"
END_DATE = "20261108"


def user_agent():
    contact = os.environ.get("WIKI_CONTACT")
    if not contact:
        raise SystemExit("Set WIKI_CONTACT (an email or URL) before calling the Wikipedia API.")
    return f"SpikeOrStay-backtest/0.1 ({contact})"


def get(url, params=None, max_attempts=5):
    """GET with the required User-Agent, retrying with backoff on 429 (rate limit)."""
    for attempt in range(max_attempts):
        resp = requests.get(url, params=params, headers={"User-Agent": user_agent()}, timeout=30)
        if resp.status_code != 429:
            return resp
        time.sleep(2 ** attempt)
    resp.raise_for_status()


def resolve_title(title):
    """Return (exists, canonical_title, redirected_from) for an article title.

    The pageviews API does NOT follow redirects, so we must always query the
    canonical title or we'd be counting views of a redirect stub (~0).
    """
    params = {"action": "query", "titles": title, "redirects": 1, "format": "json"}
    resp = get(ACTION_API, params=params)
    resp.raise_for_status()
    query = resp.json()["query"]

    canonical = title
    redirected_from = None
    for key in ("normalized", "redirects"):
        for item in query.get(key, []):
            if item["from"] == canonical:
                if key == "redirects":
                    redirected_from = canonical
                canonical = item["to"]

    page = next(iter(query["pages"].values()))
    exists = "missing" not in page
    return exists, canonical, redirected_from


def fetch_daily_pageviews(title):
    """Return the raw list of daily items for `title`, using the disk cache.

    Days with zero views are simply absent from the API response; filling
    them in is the caller's job (see series.py).
    """
    article = title.replace(" ", "_")
    cache_file = CACHE_DIR / f"{article.replace('/', '%2F')}__{START_DATE}_{END_DATE}.json"
    if cache_file.exists():
        return json.loads(cache_file.read_text())

    url = f"{PAGEVIEWS_API}/{requests.utils.quote(article, safe='')}/daily/{START_DATE}00/{END_DATE}00"
    resp = get(url)
    if resp.status_code == 404:
        items = []  # no views recorded at all for this title
    else:
        resp.raise_for_status()
        items = resp.json()["items"]

    CACHE_DIR.mkdir(exist_ok=True)
    cache_file.write_text(json.dumps(items))
    return items
