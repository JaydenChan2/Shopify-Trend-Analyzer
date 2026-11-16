"""Step A: check every row in trends.csv points at a usable title.

Rules:
  - `article` must exist and not be a redirect, UNLESS `valid_until` is set
    (the article was standalone until that date, e.g. Air fryer).
  - every title in `former_titles` must currently redirect to `article`
    (i.e. it really is an old name of the same page, safe to sum).

Usage: python verify_titles.py
"""
import csv
from pathlib import Path

from wiki import resolve_title

TRENDS_CSV = Path(__file__).parent / "trends.csv"


def check_row(row):
    problems = []
    exists, canonical, _ = resolve_title(row["article"])
    if not exists:
        problems.append("article MISSING")
    elif canonical != row["article"]:
        if row["valid_until"]:
            pass  # expected: was standalone until valid_until
        else:
            problems.append(f"article REDIRECTS -> {canonical}")

    for former in filter(None, row["former_titles"].split(";")):
        f_exists, f_canonical, _ = resolve_title(former)
        if not f_exists or f_canonical != row["article"]:
            problems.append(f"former title '{former}' resolves to '{f_canonical}' (exists={f_exists})")
    return problems


def main():
    total_problems = 0
    with open(TRENDS_CSV, newline="") as f:
        for row in csv.DictReader(f):
            problems = check_row(row)
            total_problems += len(problems)
            extras = []
            if row["former_titles"]:
                extras.append(f"+{len(row['former_titles'].split(';'))} former")
            if row["valid_until"]:
                extras.append(f"until {row['valid_until']}")
            status = "ok" if not problems else "; ".join(problems)
            print(f"{row['name']:<24} {row['article']:<28} {status} {' '.join(extras)}")
    print(f"\n{total_problems} problem(s).")


if __name__ == "__main__":
    main()
