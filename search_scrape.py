#!/usr/bin/env python3
"""
search_scrape.py

Scrape any Twitter/X search query via the SearchTimeline endpoint

    ./search_scrape.py "moon filter:media lang:en"
    ./search_scrape.py "conversation_id:20"
    ./search_scrape.py "from:nasa since:2026-01-01 -filter:replies"
    ./search_scrape.py "#skynet min_faves:100" --product Top

Reuses timeline_scrape.py's auth-token rotation, header building, entry
parsing (get_entries/iter_tweet_results/get_cursor), and row extraction -
keep both files in the same directory (and the same auth_tokens.txt).

Usage:
    ./search_scrape.py "<query>" [--product Latest|Top] [--max-tweets N] [--no-csv] [--guest]
"""

import argparse
import csv
import glob
import json
import os
import re
import secrets
import sys
import time
from datetime import datetime

import timeline_scrape as ts  # same directory - auth tokens, headers, entry/row extraction

STUCK_GIVEUP = 2  # give up after this many pages in a row with no new tweets / no cursor advance
                  # (separate from timeline_scrape.py's own STUCK_GIVEUP so changing it here doesn't affect that script)
INTERVAL = 0      # sleep n seconds between successful requests


def slugify(query, maxlen=60):
    slug = re.sub(r"[^A-Za-z0-9]+", "_", query).strip("_")
    return slug[:maxlen] or "query"


def build_csv(dest, query):
    rows = {}
    for fp in sorted(glob.glob(os.path.join(dest, "*.json"))):
        with open(fp) as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                continue
        entries, layout = ts.get_entries(data)
        for raw_result in ts.iter_tweet_results(entries, layout):
            row = ts.extract_row(raw_result)
            if row and row[0]:
                result = ts.unwrap_tweet_result(raw_result)
                screen_name = ts.screen_name_of(
                    (result or {}).get("core", {}).get("user_results", {}).get("result", {})
                )
                if screen_name:
                    row[2] = f"@{screen_name} - {row[2]}"
                rows[row[0]] = row  # dedup by tweet id, last write wins

    if not rows:
        print(f"No tweets found for query {query!r} - skipping CSV write.")
        return None

    csv_path = f"{dest}.csv"
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            ["Id", "Date", "Text", "Replies", "ReTweets", "Quotes", "Likes", "Views", "Source", "Birdwatch", "ConversationId", "Url"]
        )
        for tid in sorted(rows.keys(), key=lambda x: int(x) if x.isdigit() else 0):
            writer.writerow(rows[tid])

    print(f"CSV written to {csv_path} ({len(rows)} unique tweets)")
    return csv_path


def scrape_search(query, product="Latest", max_tweets=None, no_csv=False, guest=False):
    if guest and not ts.GUEST_BEARER_TOKEN:
        sys.exit("guest bearer_token not provided - fill in GUEST_BEARER_TOKEN in timeline_scrape.py.")
    if not guest and not ts.AUTH_TOKENS:
        sys.exit("AUTH_TOKENS / auth_tokens.txt is empty - populate the list before running (or pass --guest).")

    csrf_token = secrets.token_hex(16)
    now = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    dest = f"{slugify(query)}-{now}"
    os.makedirs(dest, exist_ok=True)

    session = ts.requests.Session()
    guest_token = None
    if guest:
        tokens_max = 0
        token_idx = 0
        guest_token = ts.get_guest_token(session)
    else:
        tokens_max = len(ts.AUTH_TOKENS) - 1
        token_idx = ts.load_token_idx(len(ts.AUTH_TOKENS))

    def maybe_build_csv():
        if no_csv:
            return None
        return build_csv(dest, query)

    count = 0
    pages_fetched = 0
    counter = 0  # unique tweets collected so far
    consecutive_errors = 0
    stuck_count = 0
    seen_ids = set()
    cursor = None
    start = time.time()

    while True:
        count_next = count + 1
        if guest:
            headers = ts.build_guest_headers(guest_token)
            token_label = f"guest …{guest_token[-4:]}"
        else:
            auth_token = ts.AUTH_TOKENS[token_idx]
            headers = ts.build_headers(csrf_token, auth_token)
            token_label = f"\x1b[1m{token_idx:02d}\x1b[0m …{auth_token[-4:]}"

        variables = {
            "rawQuery": query,
            "count": 20,
            "querySource": "typed_query",
            "product": product,
        }
        if cursor:
            variables["cursor"] = cursor

        cursor_label = f"…{cursor[-24:]}" if cursor else "(start)"
        print(
            f"page \x1b[40m {count_next} \x1b[0m | elapsed: {int(time.time()-start)}s | "
            f"token: {token_label} | product: {product} | query: {query!r} | "
            f"cursor: {cursor_label} | tweets: {counter}"
        )

        req_params = {
            "variables": json.dumps(variables, separators=(",", ":")),
            "features": json.dumps(ts.FEATURES, separators=(",", ":")),
        }

        resp = session.get(ts.URL, headers=headers, params=req_params)

        out_path = os.path.join(dest, f"{count_next}.json")

        # Treat any non-200 (e.g. a 429 rate limit) the same as an API error
        # in the body - rotate/refresh and retry rather than assuming JSON.
        if resp.status_code != 200:
            consecutive_errors += 1
            print(f"[!] HTTP {resp.status_code} on token {token_label}")
            with open(out_path, "w") as f:
                f.write(resp.text)
            pages_fetched += 1
            if consecutive_errors >= ts.MAX_CONSECUTIVE_ERRORS:
                print(f"[!] {consecutive_errors} consecutive errors - giving up.")
                maybe_build_csv()
                print(f"Partial results: {counter:,} unique tweets for query {query!r} saved to {dest}/")
                return dest
            backoff = min(ts.BACKOFF_BASE * (2 ** (consecutive_errors - 1)), ts.BACKOFF_MAX)
            if guest:
                print(f"   -> refreshing guest token, retrying in {backoff}s "
                      f"({consecutive_errors}/{ts.MAX_CONSECUTIVE_ERRORS} consecutive errors)")
                guest_token = ts.get_guest_token(session, force_refresh=True)
            else:
                print(f"   -> retrying with the next token in {backoff}s "
                      f"({consecutive_errors}/{ts.MAX_CONSECUTIVE_ERRORS} consecutive errors)")
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                ts.save_token_idx(token_idx)
            time.sleep(backoff)
            continue

        try:
            data = resp.json()
        except ValueError:
            print(f"!! non-JSON response (status {resp.status_code}), saving raw and stopping")
            with open(out_path, "w") as f:
                f.write(resp.text)
            pages_fetched += 1
            break

        with open(out_path, "w") as f:
            json.dump(data, f)
        pages_fetched += 1

        api_errors = data.get("errors")
        if api_errors:
            consecutive_errors += 1
            print(f"[!] API error on token {token_label} (status {resp.status_code}): {api_errors}")

            if consecutive_errors >= ts.MAX_CONSECUTIVE_ERRORS:
                print(f"[!] {consecutive_errors} consecutive API errors - giving up.")
                maybe_build_csv()
                print(f"Partial results: {counter:,} unique tweets for query {query!r} saved to {dest}/")
                return dest

            backoff = min(ts.BACKOFF_BASE * (2 ** (consecutive_errors - 1)), ts.BACKOFF_MAX)
            if guest:
                print(f"   -> refreshing guest token, retrying in {backoff}s "
                      f"({consecutive_errors}/{ts.MAX_CONSECUTIVE_ERRORS} consecutive errors)")
                guest_token = ts.get_guest_token(session, force_refresh=True)
            else:
                print(f"   -> retrying with the next token in {backoff}s "
                      f"({consecutive_errors}/{ts.MAX_CONSECUTIVE_ERRORS} consecutive errors)")
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                ts.save_token_idx(token_idx)
            time.sleep(backoff)
            continue

        consecutive_errors = 0
        remaining = ts.print_rate_limits(resp.headers)
        if guest and remaining is not None and remaining <= ts.GUEST_RATE_LIMIT_REFRESH_THRESHOLD:
            print(f"[*] Guest token has {remaining} request(s) left - rotating to a fresh one")
            guest_token = ts.get_guest_token(session, force_refresh=True)

        entries, layout = ts.get_entries(data)
        tweets = list(ts.iter_tweet_results(entries, layout))
        next_cursor = ts.get_cursor(entries, "Bottom")

        if len(tweets) == 0:
            print(f"[*] Search index returned 0 tweets on this page (status {resp.status_code})")
            print(f"[*] All done - completed in {int(time.time()-start)} seconds")
            if not guest:
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                ts.save_token_idx(token_idx)
            maybe_build_csv()
            print(f"Downloaded {counter:,} unique tweets for query {query!r} to {dest}/")
            return dest

        page_ids = []
        for t in tweets:
            result = ts.unwrap_tweet_result(t)
            rid = (result or {}).get("rest_id")
            if rid is not None:
                try:
                    page_ids.append(int(rid))
                except ValueError:
                    pass

        new_ids = [pid for pid in page_ids if pid not in seen_ids]
        seen_ids.update(page_ids)
        counter = len(seen_ids)

        if max_tweets is not None and counter >= max_tweets:
            print(f"[*] All done - completed in {int(time.time()-start)} seconds")
            if not guest:
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                ts.save_token_idx(token_idx)
            maybe_build_csv()
            print(f"Downloaded {counter:,} unique tweets for query {query!r} to {dest}/")
            return dest

        if not next_cursor:
            print(f"[*] No further cursor - reached end of results.")
            if not guest:
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                ts.save_token_idx(token_idx)
            maybe_build_csv()
            print(f"Downloaded {counter:,} unique tweets for query {query!r} to {dest}/")
            return dest

        made_progress = bool(new_ids) and next_cursor != cursor
        if made_progress:
            stuck_count = 0
        else:
            stuck_count += 1
            print(f"[!] No new tweets / cursor didn't advance ({stuck_count}/{STUCK_GIVEUP} stuck pages)")
            if stuck_count >= STUCK_GIVEUP:
                print("\u2717 Cursor pagination stalled - stopping here.")
                if not guest:
                    token_idx = token_idx + 1 if token_idx < tokens_max else 0
                    ts.save_token_idx(token_idx)
                maybe_build_csv()
                print(f"Partial results: {counter:,} unique tweets for query {query!r} saved to {dest}/")
                return dest

        cursor = next_cursor
        if not guest:
            token_idx = token_idx + 1 if token_idx < tokens_max else 0
            ts.save_token_idx(token_idx)
        count += 1
        time.sleep(INTERVAL)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Scrape any X search query via the SearchTimeline endpoint"
    )
    parser.add_argument("query", help='raw search query, e.g. "moon filter:media" or "conversation_id:123"')
    parser.add_argument(
        "--product",
        dest="product",
        default="Latest",
        choices=["Latest", "Top"],
        help="SearchTimeline ranking - Latest (chronological) or Top (engagement-ranked). Default: Latest.",
    )
    parser.add_argument(
        "--max-tweets",
        dest="max_tweets",
        type=int,
        default=None,
        help="Stop once this many unique tweets are collected. Highly recommended - without it "
        "the script runs until the query is exhausted or every token gets rate-limited.",
    )
    parser.add_argument(
        "--no-csv",
        dest="no_csv",
        action="store_true",
        help="Disable CSV writes entirely - only the raw per-page JSON files are saved.",
    )
    parser.add_argument(
        "--guest",
        dest="guest",
        action="store_true",
        help="Use a single rotating guest token (GUEST_BEARER_TOKEN in timeline_scrape.py) instead of AUTH_TOKENS.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    scrape_search(
        args.query,
        product=args.product,
        max_tweets=args.max_tweets,
        no_csv=args.no_csv,
        guest=args.guest,
    )
