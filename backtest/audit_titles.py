"""Audit each article's history for things that would distort its pageview series.

The pageviews API counts views per exact title, so these all matter:
  - created after data starts  -> no pre-trend history (onset falls back to threshold rule)
  - was a redirect for a period -> views during that period are ~0 (or went elsewhere)
  - page was moved (renamed)    -> views before the move are under the OLD title
  - merges                      -> content (and readers) may have come from another title
  - incoming redirects with lots of views -> part of the interest is counted elsewhere

Usage: python audit_titles.py                 # all articles in trends.csv
       python audit_titles.py "Title A" "B"   # specific titles
"""
import csv
import re
import sys
from datetime import date
from pathlib import Path

import requests

import wiki

TRENDS_CSV = Path(__file__).parent / "trends.csv"
REDIRECT_MAX_BYTES = 300      # revisions smaller than this are treated as redirects
REDIRECT_SHARE_FLAG = 0.05    # flag incoming redirects with >5% of the target's views
REDIRECT_MIN_DAYS = 7         # ignore same-day blank-and-revert vandalism
DATA_START_ISO = "2015-07-01"


def days_between(a, b):
    return (date.fromisoformat(b) - date.fromisoformat(a)).days


def api_get(params):
    params = {**params, "format": "json"}
    resp = wiki.get(wiki.ACTION_API, params=params)
    resp.raise_for_status()
    return resp.json()


def all_revisions(title):
    revisions, params = [], {"action": "query", "prop": "revisions", "titles": title,
                             "rvprop": "timestamp|size|comment", "rvlimit": "max", "rvdir": "newer"}
    while True:
        data = api_get(params)
        revisions += next(iter(data["query"]["pages"].values())).get("revisions", [])
        if "continue" not in data:
            return revisions
        params.update(data["continue"])


def incoming_redirects(title):
    data = api_get({"action": "query", "prop": "redirects", "titles": title, "rdlimit": "max"})
    page = next(iter(data["query"]["pages"].values()))
    return [r["title"] for r in page.get("redirects", [])]


def total_monthly_views(title):
    """Total views over the whole period (monthly granularity: cheap, not cached)."""
    article = requests.utils.quote(title.replace(" ", "_"), safe="")
    url = f"{wiki.PAGEVIEWS_API}/{article}/monthly/{wiki.START_DATE}00/{wiki.END_DATE}00"
    resp = wiki.get(url)
    if resp.status_code == 404:
        return 0
    resp.raise_for_status()
    return sum(item["views"] for item in resp.json()["items"])


def audit(title):
    flags = []
    revs = all_revisions(title)
    if not revs:
        return ["NO REVISIONS (page missing?)"]

    created = revs[0]["timestamp"][:10]
    if created > DATA_START_ISO:
        flags.append(f"created {created} (after data start)")

    # Redirect periods: consecutive runs of tiny revisions.
    in_redirect, start = False, None
    for rev in revs:
        is_redirect = rev["size"] < REDIRECT_MAX_BYTES
        if is_redirect and not in_redirect:
            start = rev["timestamp"][:10]
        end = rev["timestamp"][:10]
        if not is_redirect and in_redirect and end >= DATA_START_ISO and days_between(start, end) >= REDIRECT_MIN_DAYS:
            flags.append(f"was a redirect {start} -> {end}")
        in_redirect = is_redirect
    if in_redirect:
        flags.append(f"IS CURRENTLY A REDIRECT (since {start})")

    for rev in revs:
        comment = rev.get("comment", "")
        if rev["timestamp"][:10] < DATA_START_ISO:
            continue
        if "moved page" in comment:
            flags.append(f"moved {rev['timestamp'][:10]}: {comment[:100]}")
        elif re.search(r"\bmerg(ed|ing)\b", comment, re.IGNORECASE):
            flags.append(f"merge mention {rev['timestamp'][:10]}: {comment[:100]}")

    target_views = total_monthly_views(title)
    for redirect in incoming_redirects(title):
        views = total_monthly_views(redirect)
        if target_views and views / target_views > REDIRECT_SHARE_FLAG:
            flags.append(f"incoming redirect '{redirect}' has {views / target_views:.0%} of target's views")
    return flags


def main():
    titles = sys.argv[1:]
    if not titles:
        with open(TRENDS_CSV, newline="") as f:
            titles = [row["article"] for row in csv.DictReader(f)]
    for title in titles:
        flags = audit(title)
        print(f"{title}: {'clean' if not flags else ''}")
        for flag in flags:
            print(f"    - {flag}")


if __name__ == "__main__":
    main()
