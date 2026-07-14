#!/usr/bin/env python3
"""
timeline_scrape.py

Grab all raw tweets and replies from a user timeline via the SearchTimeline

The search query can optionally be bounded once at the start with:
  --until <date>    adds until:<date> to the query - tweets up to but NOT
                     including that date/time. Formats: YYYY-MM-DD,
                     YYYY-MM-DD_HH:MM:SS, or YYYY-MM-DD_HH:MM:SS_UTC.
  --since <date>    adds since:<date> to the query - tweets from that
                     date/time onward. Same formats as --until.
  --max-id <id>     adds max_id:<id> to the query - search backwards from
                     this tweet id.
  --since-id <id>   adds since_id:<id> to the query - only tweets newer
                     than this tweet id.

--update is a shortcut useful for cronjobs: it looks up the most recently saved
CSV for the given user, reads the last (highest) tweet id from it, and
runs with --since-id set to that id - so only new tweets are fetched. If
no prior CSV exists yet, it falls back to a normal full scan.

When done, builds a CSV of all downloaded JSON with columns:
Id,Date,Text,Replies,ReTweets,Likes,Views,Source,Birdwatch,ConversationId,Url
(text includes the tweet's first linked URL and, for quote-tweets, an
inline "[@user] quoted text url" or "[deleted tweet]" suffix

Usage:
    ./timeline_scrape.py <username> [--max-tweets N] [--until DATE] [--since DATE] [--max-id ID] [--since-id ID] [--update] [--no-csv]

    --max-tweets is optional but highly recommended - without it the script
    keeps paging forever until it either runs out of tweets or every token
    in AUTH_TOKENS gets rate-limited.
"""

import argparse
import csv
import glob
import json
import os
import re
import secrets
import sys
import tempfile
import time
from datetime import datetime
import requests

# add at least 20 auth_tokens here to be safe.
# each account will make one request every 20 seconds (900sec / 20 = 45 requests)
# which is below the 50 per 15 minute reset (there is a 24hr limit as well)
# you can restart next batch using <max_id> passed as an option to the script,
# if you exceed rate-limits, at a later time.
# The last-used token index is persisted to TOKEN_IDX_FILE (see below), so if
# you run this script back-to-back over many users, each run picks up
# rotation where the last one left off instead of always hammering token 0.
AUTH_TOKENS = [
  #"adfadfdf3443242323232adafafaf22222231313",
  #"adf232322423423423232adbcdfdfd3333333434",
  #"adfdfaf332442423423423424234234342424323"
]

INTERVAL = 0 # sleep n seconds between successful requests
PRODUCT = "Latest"  # Latest | Top

MAX_CONSECUTIVE_ERRORS = 5  # give up after this many API errors in a row
BACKOFF_BASE = 2  # seconds; doubles each consecutive error, capped below
BACKOFF_MAX = 60  # seconds

STUCK_GIVEUP = 5  # give up after this many pages in a row with no new tweets / no cursor advance

# Persists the last-used auth token index across separate invocations of this
# script (e.g. looping over many users back-to-back). Without this, every
# invocation restarts at AUTH_TOKENS[0], so runs that bail out quickly (no
# new tweets, immediate end-of-results, etc.) hammer the first token instead
# of rotating evenly through the whole list.
TOKEN_IDX_FILE = os.path.join(tempfile.gettempdir(), "timeline_scrape_token_idx")

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}(_\d{2}:\d{2}:\d{2}(_UTC)?)?$")

BEARER_TOKEN = (
    "AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4"
    "%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
)

URL = "https://api.twitter.com/graphql/gkjsKepM6gl_HmFWoWKfgg/SearchTimeline"

FEATURES = {
    "android_graphql_skip_api_media_color_palette": False,
    "blue_business_profile_image_shape_enabled": False,
    "creator_subscriptions_subscription_count_enabled": False,
    "creator_subscriptions_tweet_preview_api_enabled": True,
    "freedom_of_speech_not_reach_fetch_enabled": False,
    "graphql_is_translatable_rweb_tweet_is_translatable_enabled": False,
    "hidden_profile_likes_enabled": False,
    "highlights_tweets_tab_ui_enabled": False,
    "interactive_text_enabled": False,
    "longform_notetweets_consumption_enabled": True,
    "longform_notetweets_inline_media_enabled": False,
    "longform_notetweets_richtext_consumption_enabled": True,
    "longform_notetweets_rich_text_read_enabled": False,
    "responsive_web_edit_tweet_api_enabled": False,
    "responsive_web_enhance_cards_enabled": False,
    "responsive_web_graphql_exclude_directive_enabled": True,
    "responsive_web_graphql_skip_user_profile_image_extensions_enabled": False,
    "responsive_web_graphql_timeline_navigation_enabled": False,
    "responsive_web_media_download_video_enabled": False,
    "responsive_web_text_conversations_enabled": False,
    "responsive_web_twitter_article_tweet_consumption_enabled": False,
    "responsive_web_twitter_blue_verified_badge_is_enabled": True,
    "rweb_lists_timeline_redesign_enabled": True,
    "spaces_2022_h2_clipping": True,
    "spaces_2022_h2_spaces_communities": True,
    "standardized_nudges_misinfo": False,
    "subscriptions_verification_info_enabled": True,
    "subscriptions_verification_info_reason_enabled": True,
    "subscriptions_verification_info_verified_since_enabled": True,
    "super_follow_badge_privacy_enabled": False,
    "super_follow_exclusive_tweet_notifications_enabled": False,
    "super_follow_tweet_api_enabled": False,
    "super_follow_user_api_enabled": False,
    "tweet_awards_web_tipping_enabled": False,
    "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": False,
    "tweetypie_unmention_optimization_enabled": False,
    "unified_cards_ad_metadata_container_dynamic_card_content_query_enabled": False,
    "verified_phone_label_enabled": False,
    "vibe_api_enabled": False,
    "view_counts_everywhere_api_enabled": True,
    "responsive_web_grok_analyze_button_fetch_trends_enabled": True,
    "creator_subscriptions_quote_tweet_preview_enabled": False,
    "profile_label_improvements_pcf_label_in_post_enabled": False,
    "rweb_tipjar_consumption_enabled": True,
    "rweb_video_timestamps_enabled": True,
    "c9s_tweet_anatomy_moderator_badge_enabled": True,
    "communities_web_enable_tweet_community_results_fetch": True,
    "premium_content_api_read_enabled": False,
    "articles_preview_enabled": True,
    "responsive_web_grok_analyze_post_followups_enabled": False,
}

TWITTER_EPOCH_MS = 1288834974657  # snowflake epoch offset, in ms

def snowflake_epoch_seconds(tweet_id):
    return ((int(tweet_id) >> 22) + TWITTER_EPOCH_MS) / 1000

def format_duration(seconds):
    seconds = int(seconds)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    return f"{hours} hours {minutes} minutes {seconds} seconds"

def strip_html(s):
    return re.sub(r"<[^>]+>", "", s or "").strip()

def get_entries(data):
    """Flatten entries across every instruction (tweets can arrive via
    TimelineAddEntries, and cursors via either an entry in that list or a
    standalone TimelineReplaceEntry instruction)."""
    try:
        instructions = data["data"]["search_by_raw_query"]["search_timeline"]["timeline"]["instructions"]
    except (KeyError, TypeError):
        return []
    entries = []
    for instr in instructions or []:
        entries.extend(instr.get("entries", []) or [])
        if "entry" in instr:
            entries.append(instr["entry"])
    return entries


def tweet_entries(entries):
    return [e for e in entries if e.get("entryId", "").startswith("tweet-")]

def tweet_result_of(entry):
    try:
        return entry["content"]["itemContent"]["tweet_results"]["result"]
    except (KeyError, TypeError):
        return None

def get_cursor(entries, cursor_type="Bottom"):
    for e in entries:
        content = e.get("content", {}) or {}
        if content.get("cursorType") == cursor_type:
            return content.get("value")
    return None

def print_rate_limits(headers):
    remaining = headers.get("x-rate-limit-remaining")
    limit = headers.get("x-rate-limit-limit")
    reset = headers.get("x-rate-limit-reset")
    if remaining is None:
        print("x-rate-limit: (missing headers)")
        return
    reset_str = ""
    if reset:
        try:
            reset_str = datetime.fromtimestamp(int(reset)).strftime("%a %T")
        except (ValueError, OSError):
            reset_str = reset
    print(f"\x1b[32m{remaining}/{limit}\x1b[0m reset: \x1b[94m{reset_str}\x1b[0m")


def load_token_idx(tokens_count):
    """Read the last-used auth token index from TOKEN_IDX_FILE so this run
    picks up rotation where the previous invocation left off, rather than
    always starting at AUTH_TOKENS[0]."""
    try:
        with open(TOKEN_IDX_FILE) as f:
            idx = int(f.read().strip())
    except (OSError, ValueError):
        return 0
    if tokens_count <= 0:
        return 0
    return idx % tokens_count

def save_token_idx(idx):
    try:
        with open(TOKEN_IDX_FILE, "w") as f:
            f.write(str(idx))
    except OSError:
        pass

def build_headers(csrf_token, auth_token):
    return {
        "Authorization": f"Bearer {BEARER_TOKEN}",
        "User-Agent": "TwitterAndroid/10.21.1",
        "X-Csrf-Token": csrf_token,
        "Cookie": f"ct0={csrf_token}; auth_token={auth_token}",
    }

def validate_date(value, flag):
    if not DATE_RE.match(value):
        print(
            f"[!] {flag} value '{value}' doesn't match "
            f"YYYY-MM-DD[_HH:MM:SS[_UTC]] - passing it through to the query as-is."
        )
    return value

def build_query(user, until=None, since=None, max_id=None, since_id=None):
    query = f"include:nativeretweets from:{user}"
    if since:
        query += f" since:{validate_date(since, '--since')}"
    if until:
        query += f" until:{validate_date(until, '--until')}"
    if since_id:
        query += f" since_id:{since_id}"
    if max_id:
        query += f" max_id:{max_id}"
    return query

def scrape(user, max_tweets=None, until=None, since=None, max_id=None, since_id=None, no_csv=False):
    if not AUTH_TOKENS:
        sys.exit("AUTH_TOKENS is empty - populate the list before running.")

    csrf_token = secrets.token_hex(16)
    query = build_query(user, until=until, since=since, max_id=max_id, since_id=since_id)

    now = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    dest = f"{user}-{now}"
    os.makedirs(dest, exist_ok=True)

    def maybe_build_csv():
        if no_csv:
            # print(f"--no-csv set - skipping CSV write (raw JSON pages remain in {dest}/)")
            return None
        return build_csv(dest, user)

    def write_info(status, pages_fetched, csv_path):
        elapsed = int(time.time() - start)
        lines = [
            f"user: @{user}",
            f"query: {query}",
            "",
            f"status: {status}",
            f"finished: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            f"elapsed_seconds: {elapsed}",
            f"pages_fetched: {pages_fetched}",
            f"unique_tweets: {counter}",
            f"csv: {csv_path if csv_path else '(none written)'}",
            "",
            "options:",
            f"  max_tweets: {max_tweets if max_tweets is not None else 'unbounded'}",
            f"  since: {since or '(none)'}",
            f"  until: {until or '(none)'}",
            f"  since_id: {since_id or '(none)'}",
            f"  max_id: {max_id or '(none)'}",
            f"  no_csv: {no_csv}",
        ]
        info_path = os.path.join(dest, "info.txt")
        with open(info_path, "w") as f:
            f.write("\n".join(lines) + "\n")
        # print(f"Info written to {info_path}")
        return info_path

    session = requests.Session()
    tokens_max = len(AUTH_TOKENS) - 1
    token_idx = load_token_idx(len(AUTH_TOKENS))
    count = 0
    pages_fetched = 0
    counter = 0  # unique tweets collected so far
    consecutive_errors = 0
    stuck_count = 0
    seen_ids = set()
    cursor = None
    exit_status = "completed"
    start = time.time()

    while True:
        count_next = count + 1
        auth_token = AUTH_TOKENS[token_idx]
        headers = build_headers(csrf_token, auth_token)

        variables = {
            "rawQuery": query,
            "count": 20,
            "querySource": "typed_query",
            "product": PRODUCT,
        }
        if cursor:
            variables["cursor"] = cursor

        cursor_label = f"…{cursor[-24:]}" if cursor else "(start)"
        print(
            f"page \x1b[40m {count_next} \x1b[0m | elapsed: {int(time.time()-start)}s | "
            f"token: \x1b[1m{token_idx:02d}\x1b[0m …{auth_token[-4:]} | "
            f"user: @{user} | cursor: {cursor_label} | tweets: {counter}"
        )

        resp = session.get(
            URL,
            headers=headers,
            params={
                "variables": json.dumps(variables, separators=(",", ":")),
                "features": json.dumps(FEATURES, separators=(",", ":")),
            },
        )

        out_path = os.path.join(dest, f"{count_next}.json")
        try:
            data = resp.json()
        except ValueError:
            print(f"!! non-JSON response (status {resp.status_code}), saving raw and stopping")
            with open(out_path, "w") as f:
                f.write(resp.text)
            pages_fetched += 1
            exit_status = f"stopped - non-JSON response (status {resp.status_code})"
            break

        with open(out_path, "w") as f:
            json.dump(data, f)
        pages_fetched += 1

        api_errors = data.get("errors")
        if api_errors:
            consecutive_errors += 1
            print(f"[!] API error on token …{auth_token[-4:]} (status {resp.status_code}): {api_errors}")

            if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                print(
                    f"[!] {consecutive_errors} consecutive API errors - giving up "
                    f"(this usually means the backend is down, not a single bad token)."
                )
                csv_path = maybe_build_csv()
                write_info(
                    f"partial - {consecutive_errors} consecutive API errors, gave up",
                    pages_fetched,
                    csv_path,
                )
                print(f"Partial results: {counter:,} unique tweets from @{user} saved to {dest}/")
                return dest

            backoff = min(BACKOFF_BASE * (2 ** (consecutive_errors - 1)), BACKOFF_MAX)
            print(
                f"   -> retrying with the next token in {backoff}s "
                f"({consecutive_errors}/{MAX_CONSECUTIVE_ERRORS} consecutive errors)"
            )
            token_idx = token_idx + 1 if token_idx < tokens_max else 0
            save_token_idx(token_idx)
            time.sleep(backoff)
            continue

        consecutive_errors = 0
        entries = get_entries(data)
        tweets = tweet_entries(entries)
        next_cursor = get_cursor(entries, "Bottom")

        hit_max = max_tweets is not None and counter >= max_tweets
        if len(tweets) == 0 or hit_max:
            end = time.time()
            if len(tweets) == 0 and not hit_max:
                print(
                    f"[*] Search index returned 0 tweets on this page "
                    f"(status {resp.status_code})"
                )
            print(f"[*] All done - completed in {int(end-start)} seconds")
            token_idx = token_idx + 1 if token_idx < tokens_max else 0
            save_token_idx(token_idx)
            csv_path = maybe_build_csv()
            status = "completed - hit --max-tweets" if hit_max else "completed - reached end of results"
            write_info(status, pages_fetched, csv_path)
            if since_id:
                age = format_duration(time.time() - snowflake_epoch_seconds(since_id))
                print(f"Downloaded {counter:,} tweets from @{user} after {since_id} ({age}) to {dest}/")
            else:
                print(f"Downloaded latest {counter:,} unique tweets from @{user} to {dest}/")
            return dest

        # date range of first/last tweet in this page
        first_created = tweet_result_of(tweets[0])
        last_created = tweet_result_of(tweets[-1])
        first_date = (first_created or {}).get("legacy", {}).get("created_at", "").replace(" +0000", "")
        last_date = (last_created or {}).get("legacy", {}).get("created_at", "").replace(" +0000", "")
        print(f"\x1b[1;96m{first_date} <----> {last_date}\x1b[0m", end=" | ")

        print_rate_limits(resp.headers)

        page_ids = []
        for t in tweets:
            r = tweet_result_of(t)
            rid = (r or {}).get("rest_id")
            if rid is not None:
                try:
                    page_ids.append(int(rid))
                except ValueError:
                    pass

        new_ids = [pid for pid in page_ids if pid not in seen_ids]
        seen_ids.update(page_ids)
        counter = len(seen_ids)

        made_progress = bool(new_ids) and next_cursor and next_cursor != cursor
        if made_progress:
            stuck_count = 0
        else:
            stuck_count += 1
            print(
                f"[!] No new tweets / cursor didn't advance "
                f"({stuck_count}/{STUCK_GIVEUP} stuck pages)"
            )
            if stuck_count >= STUCK_GIVEUP or not next_cursor:
                print("\u2717 Cursor pagination stalled - stopping here.")
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                save_token_idx(token_idx)
                csv_path = maybe_build_csv()
                write_info("partial - cursor pagination stalled", pages_fetched, csv_path)
                print(f"Partial results: {counter:,} unique tweets from @{user} saved to {dest}/")
                return dest

        cursor = next_cursor
        token_idx = token_idx + 1 if token_idx < tokens_max else 0
        save_token_idx(token_idx)
        count += 1
        time.sleep(INTERVAL)

    csv_path = maybe_build_csv()
    write_info(exit_status, pages_fetched, csv_path)
    print(f"Partial results: {counter:,} unique tweets from @{user} saved to {dest}/")
    return dest

def get_first_url(entities):
    urls = (entities or {}).get("urls") or []
    if urls:
        return urls[0].get("expanded_url", "")
    return ""

def strip_tco(text):
    return re.sub(r"https://t\.co/.*", "", text or "")

def clean_whitespace(t):
    if t is None:
        return ""
    t = t.replace("\n", " ")
    t = re.sub(r" {2,}", " ", t)
    return t.strip()

def format_count(n):
    if n is None or n == "":
        return ""
    try:
        return f"{int(n):,}"
    except (TypeError, ValueError):
        return ""

def unwrap_tweet_result(result):
    """Mirror jq: if(.result.tweet) then .result.tweet else .result end |
    select(.__typename == "Tweet")"""
    if not result:
        return None
    if result.get("tweet"):
        result = result["tweet"]
    if result.get("__typename") != "Tweet":
        return None
    return result

def birdwatch_value(result):
    pivot = result.get("birdwatch_pivot")
    if pivot and pivot.get("destinationUrl"):
        return pivot["destinationUrl"].replace("twitter", "x", 1)
    return ""

def build_text(result):
    legacy = result.get("legacy", {}) or {}
    note_tweet = (
        result.get("note_tweet", {}).get("note_tweet_results", {}).get("result", {})
    )
    base = note_tweet.get("text") or legacy.get("full_text", "")
    base = base.replace("&amp;", "&")

    url = get_first_url(legacy.get("entities"))
    if url:
        base = f"{base} {url}"

    quoted = result.get("quoted_status_result")
    if quoted:
        qresult = quoted.get("result", {}) or {}
        if qresult.get("__typename") == "TweetWithVisibilityResults":
            qresult = qresult.get("tweet", qresult)
        q_screen_name = (
            qresult.get("core", {})
            .get("user_results", {})
            .get("result", {})
            .get("legacy", {})
            .get("screen_name")
        )
        if q_screen_name:
            q_legacy = qresult.get("legacy", {}) or {}
            q_text = q_legacy.get("full_text", "").replace("&amp;", "&")
            q_text = strip_tco(q_text)
            q_url = get_first_url(q_legacy.get("entities"))
            base += f" [@{q_screen_name}] {q_text}{q_url}"
        else:
            base += " [deleted tweet]"

    return clean_whitespace(base)

def extract_row(entry):
    tr = entry.get("content", {}).get("itemContent", {}).get("tweet_results")
    if not tr:
        return None
    result = unwrap_tweet_result(tr.get("result"))
    if not result:
        return None

    legacy = result.get("legacy", {}) or {}
    tweet_id = legacy.get("id_str", "")
    date = (legacy.get("created_at", "") or "").replace("+0000", "UTC", 1)
    text = build_text(result)
    replies = format_count(legacy.get("reply_count"))
    retweets = format_count(legacy.get("retweet_count"))
    likes = format_count(legacy.get("favorite_count"))
    views = format_count(result.get("views", {}).get("count"))
    source = strip_html(legacy.get("source", ""))
    birdwatch = birdwatch_value(result)
    conversation_id = legacy.get("conversation_id_str", "")
    screen_name = (
        result.get("core", {})
        .get("user_results", {})
        .get("result", {})
        .get("legacy", {})
        .get("screen_name", "")
    )
    url = f"https://x.com/{screen_name}/status/{tweet_id}" if tweet_id else ""

    return [tweet_id, date, text, replies, retweets, likes, views, source, birdwatch, conversation_id, url]

def build_csv(dest, user):
    rows = {}
    for fp in sorted(glob.glob(os.path.join(dest, "*.json"))):
        with open(fp) as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                continue
        for entry in tweet_entries(get_entries(data)):
            row = extract_row(entry)
            if row and row[0]:
                rows[row[0]] = row  # dedup by tweet id, last write wins

    if not rows:
        print(f"No tweets found for @{user} - skipping CSV write.")
        return None

    csv_path = f"{dest}.csv"
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            ["Id", "Date", "Text", "Replies", "ReTweets", "Likes", "Views", "Source", "Birdwatch", "ConversationId", "Url"]
        )
        # ascending, unique by Id
        for tid in sorted(rows.keys(), key=lambda x: int(x) if x.isdigit() else 0):
            writer.writerow(rows[tid])

    print(f"CSV written to {csv_path} ({len(rows)} unique tweets)")
    return csv_path

def find_latest_csv(user):
    """Find the most recently written CSV for this user, matching the
    `{user}_max-*_*.csv` naming produced by build_csv(). Returns None if
    none exist yet."""
    candidates = glob.glob(f"{user}-*.csv")
    if not candidates:
        return None
    return max(candidates, key=os.path.getmtime)

def last_tweet_id_from_csv(csv_path):
    """Rows are written in ascending Id order, so the last data row holds
    the newest tweet id. Returns None if the file has no data rows."""
    last_id = None
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader, None)  # skip header
        for row in reader:
            if row and row[0]:
                last_id = row[0]
    return last_id

def parse_args():
    parser = argparse.ArgumentParser(
        description="Scrape all tweets from a user via X's SearchTimeline GraphQL endpoint, "
        "paginating with the response cursor."
    )
    parser.add_argument("user", help="username to scrape (without @)")
    parser.add_argument(
        "--max-tweets",
        dest="max_tweets",
        type=int,
        default=None,
        help=(
            "Stop once this many unique tweets are collected. Highly recommended - "
            "without it the script runs forever, page after page, until it either "
            "runs out of tweets or every token in AUTH_TOKENS gets rate-limited."
        ),
    )
    parser.add_argument(
        "--until",
        dest="until",
        help=(
            "Adds until:<date> to the search query - results up to but NOT including that "
            "date/time. Formats: YYYY-MM-DD, YYYY-MM-DD_HH:MM:SS, or YYYY-MM-DD_HH:MM:SS_UTC. "
            "Applied once when building the query; pagination after that is cursor-driven."
        ),
    )
    parser.add_argument(
        "--since",
        dest="since",
        help=(
            "Adds since:<date> to the search query - results from that date/time onward. "
            "Formats: YYYY-MM-DD, YYYY-MM-DD_HH:MM:SS, or YYYY-MM-DD_HH:MM:SS_UTC."
        ),
    )
    parser.add_argument(
        "--max-id",
        dest="max_id",
        help=(
            "Adds max_id:<id> to the search query to search backwards from this tweet id."
        ),
    )
    parser.add_argument(
        "--since-id",
        dest="since_id",
        help=(
            "Adds since_id:<id> to the search query - only tweets newer than this tweet id."
        ),
    )
    parser.add_argument(
        "--no-csv",
        dest="no_csv",
        action="store_true",
        help="Disable CSV writes entirely - only the raw per-page JSON files are saved.",
    )
    parser.add_argument(
        "--update",
        dest="update",
        action="store_true",
        help=(
            "Look for the most recently saved CSV for this user, read the last (highest) "
            "tweet id from it, and use that as --since-id for this run - i.e. only fetch "
            "tweets newer than what you already have. If no prior CSV is found, runs a "
            "normal full scan instead. Ideal for cronjobs. Ignored if --since-id is also "
            "given explicitly."
        ),
    )
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_args()

    since_id = args.since_id
    if args.update:
        if since_id:
            print("[!] --since-id was given explicitly - ignoring --update.")
        else:
            latest_csv = find_latest_csv(args.user)
            if latest_csv:
                last_id = last_tweet_id_from_csv(latest_csv)
                if last_id:
                    since_id = last_id
                    print(f"--update: found {latest_csv}, resuming from since_id:{since_id}")
                else:
                    print(f"--update: {latest_csv} has no data rows - running a full scan instead.")
            else:
                print(f"--update: no prior CSV found for @{args.user} - running a full scan instead.")
        if args.no_csv:
            print(
                "[!] --update with --no-csv means this run won't leave a CSV behind for "
                "the *next* --update to read from."
            )

    scrape(
        args.user,
        args.max_tweets,
        until=args.until,
        since=args.since,
        max_id=args.max_id,
        since_id=since_id,
        no_csv=args.no_csv,
    )
