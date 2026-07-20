#!/usr/bin/env python3
"""
timeline_scrape.py

Grab all raw tweets and replies from a user timeline via the SearchTimeline
endpoint. It will fallback to UserTweetsAndReplies if the account is
shadowbanned/de-indexed, however there is a rough limitation of ~3200 tweets
through it.

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
inline "[@user] quoted text url", "[quote unavailable: url]" (blocked/
suspended/protected quote), or "[deleted tweet]" suffix

Usage:
    ./timeline_scrape.py <username> [--max-tweets N] [--until DATE] [--since DATE] [--max-id ID] [--since-id ID] [--update] [--no-csv] [--alt] [--yes]

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

# auth_tokens are preferred to be loaded from an auth_tokens.txt file
# next to this script (one per line).

# add at least 20 auth_tokens to be safe.
# each account will make one request every 20 seconds (900sec / 20 = 45 requests)
# which is below the 50 per 15 minute reset (there is a 24hr limit as well)
# you can restart next batch using <max_id> passed as an option to the script,
# if you exceed rate-limits, at a later time.
# The last-used token index is persisted to TOKEN_IDX_FILE (see below), so if
# you run this script back-to-back over many users, each run picks up
# rotation where the last one left off instead of always hammering token 0.
AUTH_TOKENS_FILE = os.environ.get(
    "TWITTER_AUTH_TOKENS_FILE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "auth_tokens.txt"),
)

def _load_auth_tokens():
    try:
        with open(AUTH_TOKENS_FILE) as f:
            return [
                line.strip() for line in f
                if line.strip() and not line.strip().startswith("#")
            ]
    except OSError:
        return []

AUTH_TOKENS = _load_auth_tokens() or [
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

# Bearer token used for --guest mode (no auth_token/cookie required, works
# with SearchTimeline). Guest tokens issued against it are cached below so
# repeated runs/pages don't hit activate.json every time.
#
# Left blank in the public version - fill this in yourself to enable --guest.
# Without it, --guest will refuse to run and you'll need AUTH_TOKENS instead.
GUEST_BEARER_TOKEN = ""

# Guest tokens are valid for ~2 hours; cache the issued token here so we
# don't call guest/activate.json on every page/run.
GUEST_TOKEN_FILE = os.path.join(tempfile.gettempdir(), "timeline_scrape_guest_token")
GUEST_TOKEN_MAX_AGE = 7200  # seconds
GUEST_RATE_LIMIT_REFRESH_THRESHOLD = 1  # proactively rotate guest token at/below this many requests left

URL = "https://api.twitter.com/graphql/gkjsKepM6gl_HmFWoWKfgg/SearchTimeline"

# Fallback endpoint for shadowbanned/de-indexed accounts, which don't show
# up in SearchTimeline results at all, but limited to ~3200 tweets
# regardless of --max-tweets.
ALT_MAX_TWEETS_HINT = 3200

USER_LOOKUP_URL = "https://x.com/i/api/graphql/laYnJPCAcVo0o6pzcnlVxQ/UserByScreenName"
USER_LOOKUP_FEATURES = {
    "hidden_profile_subscriptions_enabled": True,
    "rweb_tipjar_consumption_enabled": True,
    "responsive_web_graphql_exclude_directive_enabled": True,
    "verified_phone_label_enabled": False,
    "subscriptions_verification_info_is_identity_verified_enabled": True,
    "subscriptions_verification_info_verified_since_enabled": True,
    "highlights_tweets_tab_ui_enabled": True,
    "responsive_web_twitter_article_notes_tab_enabled": True,
    "subscriptions_feature_can_gift_premium": False,
    "creator_subscriptions_tweet_preview_api_enabled": True,
    "responsive_web_graphql_skip_user_profile_image_extensions_enabled": False,
    "responsive_web_graphql_timeline_navigation_enabled": True,
}

ALT_URL = "https://x.com/i/api/graphql/bt4TKuFz4T7Ckk-VvQVSow/UserTweetsAndReplies"
ALT_FEATURES = {
    "rweb_tipjar_consumption_enabled": True,
    "responsive_web_graphql_exclude_directive_enabled": True,
    "verified_phone_label_enabled": False,
    "creator_subscriptions_tweet_preview_api_enabled": True,
    "responsive_web_graphql_timeline_navigation_enabled": True,
    "responsive_web_graphql_skip_user_profile_image_extensions_enabled": False,
    "communities_web_enable_tweet_community_results_fetch": True,
    "c9s_tweet_anatomy_moderator_badge_enabled": True,
    "articles_preview_enabled": True,
    "responsive_web_edit_tweet_api_enabled": True,
    "graphql_is_translatable_rweb_tweet_is_translatable_enabled": True,
    "view_counts_everywhere_api_enabled": True,
    "longform_notetweets_consumption_enabled": True,
    "responsive_web_twitter_article_tweet_consumption_enabled": True,
    "tweet_awards_web_tipping_enabled": False,
    "creator_subscriptions_quote_tweet_preview_enabled": False,
    "freedom_of_speech_not_reach_fetch_enabled": False,
    "standardized_nudges_misinfo": True,
    "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": True,
    "rweb_video_timestamps_enabled": True,
    "longform_notetweets_rich_text_read_enabled": True,
    "longform_notetweets_inline_media_enabled": True,
    "responsive_web_enhance_cards_enabled": False,
}
ALT_FIELD_TOGGLES = {"withArticlePlainText": True}

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

def get_instructions(data):
    try:
        return data["data"]["search_by_raw_query"]["search_timeline"]["timeline"]["instructions"], "search"
    except (KeyError, TypeError):
        pass
    try:
        return data["data"]["user"]["result"]["timeline_v2"]["timeline"]["instructions"], "user_tweets"
    except (KeyError, TypeError):
        pass
    return [], None

def get_entries(data):
    instructions, layout = get_instructions(data)
    entries = []
    for instr in instructions or []:
        entries.extend(instr.get("entries", []) or [])
        if "entry" in instr:
            entries.append(instr["entry"])
    return entries, layout

def iter_tweet_results(entries, layout):
    for e in entries:
        entry_id = e.get("entryId", "")
        content = e.get("content", {}) or {}
        if entry_id.startswith("tweet-"):
            tr = content.get("itemContent", {}).get("tweet_results")
            if tr:
                yield tr.get("result")
        elif entry_id.startswith("profile-conversation-"):
            items = content.get("items", []) or []
            if items:
                tr = items[-1].get("item", {}).get("itemContent", {}).get("tweet_results")
                if tr:
                    yield tr.get("result")

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
        return None
    reset_str = ""
    if reset:
        try:
            reset_str = datetime.fromtimestamp(int(reset)).strftime("%a %T")
        except (ValueError, OSError):
            reset_str = reset
    print(f"\x1b[32m{remaining}/{limit}\x1b[0m reset: \x1b[94m{reset_str}\x1b[0m")
    try:
        return int(remaining)
    except (TypeError, ValueError):
        return None


def load_token_idx(tokens_count):
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

def get_guest_token(session, force_refresh=False):
    """Reuse the cached guest token if it's under GUEST_TOKEN_MAX_AGE old,
    otherwise activate a new one and cache it to GUEST_TOKEN_FILE."""
    if not force_refresh:
        try:
            if time.time() - os.path.getmtime(GUEST_TOKEN_FILE) < GUEST_TOKEN_MAX_AGE:
                with open(GUEST_TOKEN_FILE) as f:
                    token = f.read().strip()
                if token:
                    return token
        except OSError:
            pass

    resp = session.post(
        "https://api.twitter.com/1.1/guest/activate.json",
        headers={"Authorization": f"Bearer {GUEST_BEARER_TOKEN}"},
    )
    try:
        token = resp.json().get("guest_token")
    except ValueError:
        token = None
    if not token:
        sys.exit(f"[!] Failed to obtain guest token (status {resp.status_code}): {resp.text}")

    with open(GUEST_TOKEN_FILE, "w") as f:
        f.write(token)
    return token

def build_guest_headers(guest_token):
    return {
        "Authorization": f"Bearer {GUEST_BEARER_TOKEN}",
        "User-Agent": "TwitterAndroid/10.21.1",
        "x-guest-token": guest_token,
    }

def lookup_user_id(session, headers, screen_name):
    variables = {
        "screen_name": screen_name,
        "includePromotedContent": False,
        "withBirdwatchNotes": True,
        "withVoice": True,
    }
    resp = session.get(
        USER_LOOKUP_URL,
        headers=headers,
        params={
            "variables": json.dumps(variables, separators=(",", ":")),
            "features": json.dumps(USER_LOOKUP_FEATURES, separators=(",", ":")),
        },
    )
    try:
        data = resp.json()
    except ValueError:
        return None
    try:
        return data["data"]["user"]["result"]["rest_id"]
    except (KeyError, TypeError):
        return None

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

def scrape(user, max_tweets=None, until=None, since=None, max_id=None, since_id=None, no_csv=False, guest=False, alt=False, yes=False):
    if guest and not GUEST_BEARER_TOKEN:
        sys.exit("guest bearer_token not provided")
    if not guest and not AUTH_TOKENS:
        sys.exit("AUTH_TOKENS / auth_tokens.txt is empty - populate the list before running (or pass --guest).")

    using_alt = alt  # may flip True mid-run if SearchTimeline comes back empty on page 1
    alt_user_id = None
    if using_alt:
        print(f"[*] --alt given - scraping @{user} via UserTweetsAndReplies from the start "
              f"(max ~{ALT_MAX_TWEETS_HINT:,} tweets on this endpoint).")

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
            f"  endpoint: {'UserTweetsAndReplies (--alt)' if alt else ('UserTweetsAndReplies (fallback after empty SearchTimeline)' if using_alt else 'SearchTimeline')}",
        ]
        info_path = os.path.join(dest, "info.txt")
        with open(info_path, "w") as f:
            f.write("\n".join(lines) + "\n")
        # print(f"Info written to {info_path}")
        return info_path

    session = requests.Session()
    if guest:
        tokens_max = 0
        token_idx = 0
        guest_token = get_guest_token(session)
    else:
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
        if guest:
            headers = build_guest_headers(guest_token)
            token_label = f"guest …{guest_token[-4:]}"
        else:
            auth_token = AUTH_TOKENS[token_idx]
            headers = build_headers(csrf_token, auth_token)
            token_label = f"\x1b[1m{token_idx:02d}\x1b[0m …{auth_token[-4:]}"

        if using_alt:
            if alt_user_id is None:
                alt_user_id = lookup_user_id(session, headers, user)
                if not alt_user_id:
                    sys.exit(f"[!] Could not resolve a user id for @{user} via UserByScreenName - aborting.")
                print(f"[*] Resolved @{user} -> user id {alt_user_id}")
            variables = {
                "userId": alt_user_id,
                "count": 20,
                "includePromotedContent": False,
                "withCommunity": True,
                "withVoice": True,
                "withV2Timeline": True,
            }
            req_url, req_features, req_field_toggles = ALT_URL, ALT_FEATURES, ALT_FIELD_TOGGLES
        else:
            variables = {
                "rawQuery": query,
                "count": 20,
                "querySource": "typed_query",
                "product": PRODUCT,
            }
            req_url, req_features, req_field_toggles = URL, FEATURES, None
        if cursor:
            variables["cursor"] = cursor

        cursor_label = f"…{cursor[-24:]}" if cursor else "(start)"
        print(
            f"page \x1b[40m {count_next} \x1b[0m | elapsed: {int(time.time()-start)}s | "
            f"token: {token_label} | endpoint: {'alt' if using_alt else 'search'} | "
            f"user: @{user} | cursor: {cursor_label} | tweets: {counter}"
        )

        req_params = {
            "variables": json.dumps(variables, separators=(",", ":")),
            "features": json.dumps(req_features, separators=(",", ":")),
        }
        if req_field_toggles:
            req_params["fieldToggles"] = json.dumps(req_field_toggles, separators=(",", ":"))

        resp = session.get(req_url, headers=headers, params=req_params)

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
            print(f"[!] API error on token {token_label} (status {resp.status_code}): {api_errors}")

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
            if guest:
                print(
                    f"   -> refreshing guest token, retrying in {backoff}s "
                    f"({consecutive_errors}/{MAX_CONSECUTIVE_ERRORS} consecutive errors)"
                )
                guest_token = get_guest_token(session, force_refresh=True)
            else:
                print(
                    f"   -> retrying with the next token in {backoff}s "
                    f"({consecutive_errors}/{MAX_CONSECUTIVE_ERRORS} consecutive errors)"
                )
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                save_token_idx(token_idx)
            time.sleep(backoff)
            continue

        consecutive_errors = 0
        entries, layout = get_entries(data)
        tweets = list(iter_tweet_results(entries, layout))
        next_cursor = get_cursor(entries, "Bottom")

        if len(tweets) == 0:
            if count_next == 1 and not using_alt:
                print(
                    f"[!] SearchTimeline returned 0 tweets on the very first page for @{user}. "
                    f"This usually means the account is shadowbanned/de-indexed from search "
                    f"rather than actually empty."
                )
                fall_back = False
                if yes:
                    fall_back = True
                    print(f"    --yes given - falling back to UserTweetsAndReplies (max ~{ALT_MAX_TWEETS_HINT:,} tweets).")
                elif not sys.stdin.isatty():
                    print("    Non-interactive session - skipping fallback. Re-run with --alt or --yes to use it directly.")
                else:
                    answer = input(
                        f"    Try UserTweetsAndReplies instead (max ~{ALT_MAX_TWEETS_HINT:,} tweets)? [y/N] "
                    ).strip().lower()
                    fall_back = answer == "y"
                if fall_back:
                    using_alt = True
                    cursor = None
                    stuck_count = 0
                    print(f"[*] Switching to UserTweetsAndReplies for @{user} ...")
                    continue

            end = time.time()
            print(
                f"[*] Search index returned 0 tweets on this page "
                f"(status {resp.status_code})"
            )
            print(f"[*] All done - completed in {int(end-start)} seconds")
            if not guest:
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                save_token_idx(token_idx)
            csv_path = maybe_build_csv()
            write_info("completed - reached end of results", pages_fetched, csv_path)
            if since_id:
                age = format_duration(time.time() - snowflake_epoch_seconds(since_id))
                print(f"Downloaded {counter:,} tweets from @{user} after {since_id} ({age}) to {dest}/")
            else:
                print(f"Downloaded latest {counter:,} unique tweets from @{user} to {dest}/")
            return dest

        # date range of first/last tweet in this page
        first_created = tweets[0]
        last_created = tweets[-1]
        first_date = (first_created or {}).get("legacy", {}).get("created_at", "").replace(" +0000", "")
        last_date = (last_created or {}).get("legacy", {}).get("created_at", "").replace(" +0000", "")
        print(f"\x1b[1;96m{first_date} <----> {last_date}\x1b[0m", end=" | ")

        remaining = print_rate_limits(resp.headers)
        if guest and remaining is not None and remaining <= GUEST_RATE_LIMIT_REFRESH_THRESHOLD:
            print(f"[*] Guest token has {remaining} request(s) left - rotating to a fresh one")
            guest_token = get_guest_token(session, force_refresh=True)

        page_ids = []
        for t in tweets:
            rid = (t or {}).get("rest_id")
            if rid is not None:
                try:
                    page_ids.append(int(rid))
                except ValueError:
                    pass

        new_ids = [pid for pid in page_ids if pid not in seen_ids]
        seen_ids.update(page_ids)
        counter = len(seen_ids)

        if max_tweets is not None and counter >= max_tweets:
            end = time.time()
            print(f"[*] All done - completed in {int(end-start)} seconds")
            if not guest:
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                save_token_idx(token_idx)
            csv_path = maybe_build_csv()
            write_info("completed - hit --max-tweets", pages_fetched, csv_path)
            if since_id:
                age = format_duration(time.time() - snowflake_epoch_seconds(since_id))
                print(f"Downloaded {counter:,} tweets from @{user} after {since_id} ({age}) to {dest}/")
            else:
                print(f"Downloaded latest {counter:,} unique tweets from @{user} to {dest}/")
            return dest

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
                if not guest:
                    token_idx = token_idx + 1 if token_idx < tokens_max else 0
                    save_token_idx(token_idx)
                csv_path = maybe_build_csv()
                write_info("partial - cursor pagination stalled", pages_fetched, csv_path)
                print(f"Partial results: {counter:,} unique tweets from @{user} saved to {dest}/")
                return dest

        cursor = next_cursor
        if not guest:
            token_idx = token_idx + 1 if token_idx < tokens_max else 0
            save_token_idx(token_idx)
        count += 1
        time.sleep(INTERVAL)

    csv_path = maybe_build_csv()
    write_info(exit_status, pages_fetched, csv_path)
    print(f"Partial results: {counter:,} unique tweets from @{user} saved to {dest}/")
    return dest

def get_media_url(media):
    mtype = media.get("type")
    if mtype == "photo":
        return media.get("media_url_https", "")
    if mtype in ("video", "animated_gif"):
        variants = media.get("video_info", {}).get("variants", []) or []
        mp4s = [v for v in variants if v.get("content_type") == "video/mp4" and v.get("url")]
        if mp4s:
            return max(mp4s, key=lambda v: v.get("bitrate") or 0)["url"]
    return ""

def expand_entities(text, legacy):
    entities = legacy.get("entities", {}) or {}
    media_list = (legacy.get("extended_entities", {}) or {}).get("media") or entities.get("media") or []
    mapping = {}
    for m in media_list:
        tco, full = m.get("url"), get_media_url(m)
        if tco and full:
            mapping[tco] = full
    for u in entities.get("urls", []) or []:
        tco, expanded = u.get("url"), u.get("expanded_url")
        if tco and expanded and tco not in mapping:
            mapping[tco] = expanded
    for tco, replacement in mapping.items():
        text = text.replace(tco, replacement)
    return text, mapping

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

def quote_unavailable_label(legacy, qresult):
    permalink = (legacy.get("quoted_status_permalink", {}) or {}).get("expanded", "")
    reason = qresult.get("reason")
    if reason:
        label = f"quote unavailable ({reason})"
    else:
        label = "quote unavailable"
    if permalink:
        return f"{label}: {permalink}"
    return label

def leading_reply_mentions(legacy):
    entities = legacy.get("entities", {}) or {}
    mentions = entities.get("user_mentions", []) or []
    display_start = (legacy.get("display_text_range") or [0])[0]
    leading = [
        m for m in mentions
        if (m.get("indices") or [None])[0] is not None
        and m["indices"][0] < display_start
    ]
    leading.sort(key=lambda m: m["indices"][0])
    names = [m.get("screen_name") for m in leading if m.get("screen_name")]
    return " ".join(f"@{n}" for n in names) + " " if names else ""

def build_text(result):
    legacy = result.get("legacy", {}) or {}
    note_tweet = (
        result.get("note_tweet", {}).get("note_tweet_results", {}).get("result", {})
    )
    note_text = note_tweet.get("text")
    if note_text:
        base = leading_reply_mentions(legacy) + note_text
    else:
        base = legacy.get("full_text", "")
    base = base.replace("&amp;", "&")

    base, mapping = expand_entities(base, legacy)

    if note_text:
        # note-tweet text is the full long-form body but doesn't inline the
        # trailing media/link t.co the way legacy full_text does - append
        # anything that didn't already land in the text.
        extras = [full for full in mapping.values() if full not in base]
        if extras:
            base = f"{base} {' '.join(extras)}"

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
            q_text, _ = expand_entities(q_text, q_legacy)
            base += f" [@{q_screen_name}] {q_text}"
        elif qresult.get("__typename") == "TweetUnavailable":
            base += f" [{quote_unavailable_label(legacy, qresult)}]"
        else:
            base += " [deleted tweet]"

    return clean_whitespace(base)

def extract_row(raw_result):
    result = unwrap_tweet_result(raw_result)
    if not result:
        return None

    legacy = result.get("legacy", {}) or {}
    tweet_id = legacy.get("id_str", "")
    date = (legacy.get("created_at", "") or "").replace("+0000", "UTC", 1)
    text = build_text(result)
    replies = format_count(legacy.get("reply_count"))
    retweets = format_count(legacy.get("retweet_count"))
    quotes = format_count(legacy.get("quote_count"))
    likes = format_count(legacy.get("favorite_count"))
    views = format_count(result.get("views", {}).get("count"))
    source = strip_html(result.get("source", ""))
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

    return [tweet_id, date, text, replies, retweets, quotes, likes, views, source, birdwatch, conversation_id, url]

def build_csv(dest, user):
    rows = {}
    for fp in sorted(glob.glob(os.path.join(dest, "*.json"))):
        with open(fp) as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                continue
        entries, layout = get_entries(data)
        for raw_result in iter_tweet_results(entries, layout):
            row = extract_row(raw_result)
            if row and row[0]:
                rows[row[0]] = row  # dedup by tweet id, last write wins

    if not rows:
        print(f"No tweets found for @{user} - skipping CSV write.")
        return None

    csv_path = f"{dest}.csv"
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            ["Id", "Date", "Text", "Replies", "ReTweets", "Quotes", "Likes", "Views", "Source", "Birdwatch", "ConversationId", "Url"]
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
        "--guest",
        dest="guest",
        action="store_true",
        help=(
            "Use a guest token instead of an AUTH_TOKENS account cookie. No login "
            "required, but subject to guest-tier rate limits and no rotation across "
            "multiple accounts. The guest token is cached to a /tmp file and reused "
            "for ~2 hours before a fresh one is activated."
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
    parser.add_argument(
        "--alt",
        dest="alt",
        action="store_true",
        help=(
            "Skip SearchTimeline and scrape via UserTweetsAndReplies from the start instead. "
            "Use this for accounts you already know are shadowbanned/de-indexed from search. "
            f"This endpoint reads the timeline directly but is capped at the last "
            f"~{ALT_MAX_TWEETS_HINT:,} tweets regardless of --max-tweets."
        ),
    )
    parser.add_argument(
        "--yes", "-y",
        dest="yes",
        action="store_true",
        help=(
            "Auto-confirm the UserTweetsAndReplies fallback prompt shown when SearchTimeline "
            "returns 0 tweets on the first page, instead of asking interactively. Useful "
            "combined with --update for unattended/cron runs."
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
        guest=args.guest,
        alt=args.alt,
        yes=args.yes,
    )
