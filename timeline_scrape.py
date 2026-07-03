#!/usr/bin/env python3
"""
timeline_scrape.py

Grab all raw tweets and replies from a user timeline via the SearchTimeline

The search query can optionally be bounded once at the start with:
  --until <date>    adds until:<date> to the query - tweets up to but NOT
                     including that date/time. Formats: YYYY-MM-DD,
                     YYYY-MM-DD_HH:MM:SS, or YYYY-MM-DD_HH:MM:SS_UTC.
  --max-id <id>     adds max_id:<id> to the query - search backwards from
                     this tweet id.

When done, builds a CSV of all downloaded JSON with columns:
Id,Date,Text,Replies,ReTweets,Likes,Views,Source,Birdwatch,ConversationId,Url
(text includes the tweet's first linked URL and, for quote-tweets, an
inline "[@user] quoted text url" or "[deleted tweet]" suffix

Usage:
    ./timeline_scrape.py <username> <max_tweets> [--until DATE] [--max-id ID]
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
import requests

# add at least 20 auth_tokens here to be safe.
# each account will make one request every 20 seconds (900sec / 20 = 45 requests)
# which is below the 50 per 15 minute reset (there is a 24hr limit as well)
# you can restart next batch using <max_id> passed as an option to the script,
# if you exceed rate-limits, at a later time.
AUTH_TOKENS = [
  #"adfadfdf3443242323232adafafaf22222231313",
  #"adf232322423423423232adbcdfdfd3333333434",
  #"adfdfaf332442423423423424234234342424323"
]

INTERVAL = 1  # sleep n seconds between successful requests
PRODUCT = "Latest"  # Latest | Top

MAX_CONSECUTIVE_ERRORS = 5  # give up after this many API errors in a row
BACKOFF_BASE = 2  # seconds; doubles each consecutive error, capped below
BACKOFF_MAX = 60  # seconds

STUCK_GIVEUP = 5  # give up after this many pages in a row with no new tweets / no cursor advance

UNTIL_RE = re.compile(r"^\d{4}-\d{2}-\d{2}(_\d{2}:\d{2}:\d{2}(_UTC)?)?$")

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


def build_headers(csrf_token, auth_token):
    return {
        "Authorization": f"Bearer {BEARER_TOKEN}",
        "User-Agent": "TwitterAndroid/10.21.1",
        "X-Csrf-Token": csrf_token,
        "Cookie": f"ct0={csrf_token}; auth_token={auth_token}",
    }

def validate_until(value):
    if not UNTIL_RE.match(value):
        print(
            f"\u26a0\ufe0f  --until value '{value}' doesn't match "
            f"YYYY-MM-DD[_HH:MM:SS[_UTC]] - passing it through to the query as-is."
        )
    return value

def build_query(user, until=None, max_id=None):
    query = f"include:nativeretweets from:{user}"
    if until:
        query += f" until:{validate_until(until)}"
    if max_id:
        query += f" max_id:{max_id}"
    return query

def scrape(user, max_tweets, until=None, max_id=None):
    if not AUTH_TOKENS:
        sys.exit("AUTH_TOKENS is empty - populate the list before running.")

    csrf_token = secrets.token_hex(16)
    query = build_query(user, until=until, max_id=max_id)

    now = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    dest = f"{user}_max-{max_tweets}_{now}"
    os.makedirs(dest, exist_ok=True)

    session = requests.Session()
    tokens_max = len(AUTH_TOKENS) - 1
    token_idx = 0
    count = 0
    counter = 0  # unique tweets collected so far
    consecutive_errors = 0
    stuck_count = 0
    seen_ids = set()
    cursor = None
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
            break

        with open(out_path, "w") as f:
            json.dump(data, f)

        api_errors = data.get("errors")
        if api_errors:
            consecutive_errors += 1
            print(f"!! API error on token …{auth_token[-4:]} (status {resp.status_code}): {api_errors}")

            if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                print(
                    f"\u2717 {consecutive_errors} consecutive API errors - giving up "
                    f"(this usually means the backend is down, not a single bad token)."
                )
                build_csv(dest, user)
                print(f"Partial results: {counter:,} unique tweets from @{user} saved to {dest}/")
                return dest

            backoff = min(BACKOFF_BASE * (2 ** (consecutive_errors - 1)), BACKOFF_MAX)
            print(
                f"   -> retrying with the next token in {backoff}s "
                f"({consecutive_errors}/{MAX_CONSECUTIVE_ERRORS} consecutive errors)"
            )
            token_idx = token_idx + 1 if token_idx < tokens_max else 0
            time.sleep(backoff)
            continue

        consecutive_errors = 0
        entries = get_entries(data)
        tweets = tweet_entries(entries)
        next_cursor = get_cursor(entries, "Bottom")

        if len(tweets) == 0 or counter >= max_tweets:
            end = time.time()
            if len(tweets) == 0 and counter < max_tweets:
                print(
                    f"\u26a0\ufe0f  Search index returned 0 tweets on this page "
                    f"(status {resp.status_code}, no 'errors' field) - this looks like a "
                    f"genuine end of available results, not a token failure."
                )
            print(f"\u2728 All done - completed in {int(end-start)} seconds")
            build_csv(dest, user)
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
                f"\u26a0\ufe0f  No new tweets / cursor didn't advance "
                f"({stuck_count}/{STUCK_GIVEUP} stuck pages)"
            )
            if stuck_count >= STUCK_GIVEUP or not next_cursor:
                print("\u2717 Cursor pagination stalled - stopping here.")
                build_csv(dest, user)
                print(f"Partial results: {counter:,} unique tweets from @{user} saved to {dest}/")
                return dest

        cursor = next_cursor
        token_idx = token_idx + 1 if token_idx < tokens_max else 0
        count += 1
        time.sleep(INTERVAL)

    build_csv(dest, user)
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

def parse_args():
    parser = argparse.ArgumentParser(
        description="Scrape all tweets from a user via X's SearchTimeline GraphQL endpoint, "
        "paginating with the response cursor."
    )
    parser.add_argument("user", help="username to scrape (without @)")
    parser.add_argument("max_tweets", type=int, help="stop once this many unique tweets are collected")
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
        "--max-id",
        dest="max_id",
        help=(
            "Adds max_id:<id> to the search query to search backwards from this tweet id. "
            "Applied once when building the query; pagination after that is cursor-driven."
        ),
    )
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_args()
    scrape(args.user, args.max_tweets, until=args.until, max_id=args.max_id)
