#!/usr/bin/env python3
"""
timeline_scrape.py

Grab all raw tweets and replies from a user timeline via the
UserTweetsAndReplies endpoint (SearchTimeline is no longer used - it's broken
upstream).

UserTweetsAndReplies pages newest-first, has no server-side date/id filter and
only reaches back roughly the last ~3200 tweets. The stream of tweets never
ends on its own, so every bound is enforced client-side against the id of each
incoming tweet (snowflake ids are time-ordered, so --since/--until dates are
converted to ids up front; dates are always interpreted as UTC):

  --since-id <id>   keep only tweets newer than this id (exclusive). Paging
                     STOPS as soon as it reaches a tweet at/before this id.
  --since <date>    keep tweets from that date/time onward (inclusive). Paging
                     STOPS as soon as it reaches an older tweet.
  --until <date>    drop tweets at/after that date/time (exclusive).
  --max-id <id>     drop tweets newer than this id (inclusive).
  Date formats: YYYY-MM-DD, YYYY-MM-DD_HH:MM:SS, YYYY-MM-DD_HH:MM:SS_UTC.
  If a date and an id are both given for the same side, the tighter one wins.

--until/--max-id can't seek: the feed is still paged from the newest tweet and
the too-new ones are discarded until the range is reached. Those pages count
against the ~3200 tweet depth, so a range far back may be unreachable.

The pinned tweet (served at the top of page 1 whatever its age) is ignored by
the stop check, so an old pinned tweet can't end the run early. It is still
kept if it falls inside the range, and dropped from the CSV if it doesn't.

--retweets switches to the UserRepostsTimeline endpoint, which returns only
the user's reposts (not their own tweets/replies). The same client-side
bounds apply. Not limited to the last 7 days.

--update is a shortcut useful for cronjobs: it looks up the most recently saved
CSV for the given user, reads the last (highest) tweet id from it, and
runs with --since-id set to that id - so paging stops the moment it catches up
to what you already have. If no prior CSV exists yet, it falls back to a normal
full scan. If the feed runs out before reaching that id (more tweets than the
endpoint's depth since the last run) a gap warning is printed.

Sessions: tokens come from auth_tokens.txt (bare auth_token per line) and from a
Nitter-style sessions.jsonl (one JSON object per line: kind, username, id,
auth_token, ct0 and optionally suspended="true"), looked up next to the script
or given with --sessions FILE (env: TWITTER_SESSIONS_FILE). Only kind "cookie"
records are used; the record's own ct0 is sent instead of a random one.
Suspended sessions are fully usable here - UserTweetsAndReplies doesn't care
(only search did) - so they're kept in the rotation like any other session and
are never put on the dead-token list, even if an older run marked them dead.

When done, builds a CSV of all downloaded JSON with columns:
Id,Date,Text,Replies,ReTweets,Quotes,Likes,Views,Source,Birdwatch,ConversationId,Url
(text includes the tweet's first linked URL and, for quote-tweets, an
inline "[@user] quoted text url", "[quote unavailable: url]" (blocked/
suspended/protected quote), or "[deleted tweet]" suffix
The CSV only contains tweets inside the --since/--until range.

Usage:
    ./timeline_scrape.py <username> [--max-tweets N] [--until DATE] [--since DATE] [--max-id ID] [--since-id ID] [--update] [--no-csv] [--guest] [--retweets] [--sessions FILE]

    Without --since/--since-id/--update/--max-tweets the script keeps paging
    until the endpoint runs out of tweets or every token in AUTH_TOKENS gets
    rate-limited.
"""

import argparse
import csv
import glob
import hashlib
import json
import os
import re
import secrets
import sys
import tempfile
import time
from datetime import datetime, timezone
import requests


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
]

SESSIONS_FILE = os.environ.get(
    "TWITTER_SESSIONS_FILE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "sessions.jsonl"),
)
SESSION_META = {}

def add_sessions(path, required=False):
    """Merge cookie sessions from a sessions.jsonl into AUTH_TOKENS/SESSION_META.
    A record here wins over a bare auth_tokens.txt entry for the same token."""
    try:
        f = open(path)
    except OSError as e:
        if required:
            sys.exit(f"[!] can't read sessions file {path}: {e}")
        return 0
    added = skipped = 0
    with f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                print(f"[!] {path}:{n} isn't valid JSON - skipping")
                skipped += 1
                continue
            if not isinstance(rec, dict) or not rec.get("auth_token") or rec.get("kind", "cookie") != "cookie":
                skipped += 1
                continue
            tok = rec["auth_token"]
            SESSION_META[tok] = {
                "username": rec.get("username") or "",
                "id": rec.get("id") or "",
                "ct0": rec.get("ct0") or "",
                "suspended": str(rec.get("suspended", "")).lower() == "true",
            }
            if tok not in AUTH_TOKENS:
                AUTH_TOKENS.append(tok)
            added += 1
    n_susp = sum(1 for m in SESSION_META.values() if m["suspended"])
    print(f"[*] sessions: {added} cookie session(s) from {path} ({n_susp} suspended)"
          + (f", {skipped} line(s) skipped (non-cookie/invalid)" if skipped else ""))
    return added

def token_tag(auth_token):
    m = SESSION_META.get(auth_token)
    if not m or not m["username"]:
        return ""
    return f"@{m['username']}{' (susp)' if m['suspended'] else ''} "

INTERVAL = 0

MAX_CONSECUTIVE_ERRORS = 5
BACKOFF_BASE = 2
BACKOFF_MAX = 60

STUCK_GIVEUP = 5

TOKEN_IDX_FILE = os.path.join(tempfile.gettempdir(), "timeline_scrape_token_idx")

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}(_\d{2}:\d{2}:\d{2}(_UTC)?)?$")

BEARER_TOKEN = (
    "AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4"
    "%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
)

GUEST_BEARER_TOKEN = ""

GUEST_TOKEN_FILE = os.path.join(tempfile.gettempdir(), "timeline_scrape_guest_token")
GUEST_TOKEN_MAX_AGE = 7200
GUEST_RATE_LIMIT_REFRESH_THRESHOLD = 1


TIMELINE_CAP_HINT = 3200

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

TIMELINE_URL = "https://x.com/i/api/graphql/bt4TKuFz4T7Ckk-VvQVSow/UserTweetsAndReplies"
TIMELINE_FEATURES = {
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
TIMELINE_FIELD_TOGGLES = {"withArticlePlainText": True}

REPOSTS_URL = "https://x.com/i/api/graphql/CnNg1YiKG7bRgi-RoIfKsw/UserRepostsTimeline"
REPOSTS_FEATURES = {
    "rweb_video_screen_enabled": False,
    "rweb_cashtags_enabled": True,
    "profile_label_improvements_pcf_label_in_post_enabled": True,
    "responsive_web_profile_redirect_enabled": True,
    "rweb_tipjar_consumption_enabled": False,
    "verified_phone_label_enabled": False,
    "creator_subscriptions_tweet_preview_api_enabled": True,
    "responsive_web_graphql_timeline_navigation_enabled": True,
    "premium_content_api_read_enabled": False,
    "communities_web_enable_tweet_community_results_fetch": True,
    "c9s_tweet_anatomy_moderator_badge_enabled": True,
    "responsive_web_grok_analyze_button_fetch_trends_enabled": False,
    "responsive_web_grok_analyze_post_followups_enabled": True,
    "rweb_cashtags_composer_attachment_enabled": True,
    "responsive_web_jetfuel_frame": True,
    "rweb_sports_post_context_enabled": True,
    "responsive_web_grok_share_attachment_enabled": True,
    "responsive_web_grok_annotations_enabled": True,
    "articles_preview_enabled": True,
    "responsive_web_edit_tweet_api_enabled": True,
    "rweb_conversational_replies_downvote_enabled": False,
    "graphql_is_translatable_rweb_tweet_is_translatable_enabled": True,
    "view_counts_everywhere_api_enabled": True,
    "longform_notetweets_consumption_enabled": True,
    "responsive_web_twitter_article_tweet_consumption_enabled": True,
    "content_disclosure_indicator_enabled": True,
    "content_disclosure_ai_generated_indicator_enabled": True,
    "responsive_web_grok_show_grok_translated_post": True,
    "responsive_web_grok_analysis_button_from_backend": True,
    "post_ctas_fetch_enabled": False,
    "freedom_of_speech_not_reach_fetch_enabled": True,
    "standardized_nudges_misinfo": True,
    "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": True,
    "longform_notetweets_rich_text_read_enabled": True,
    "longform_notetweets_inline_media_enabled": False,
    "responsive_web_nested_quote_preview_enabled": False,
    "responsive_web_grok_image_annotation_enabled": True,
    "responsive_web_grok_imagine_annotation_enabled": True,
    "responsive_web_grok_community_note_auto_translation_is_enabled": True,
    "responsive_web_enhance_cards_enabled": False,
}
REPOSTS_FIELD_TOGGLES = {"withPayments": False, "withArticlePlainText": False}

TWITTER_EPOCH_MS = 1288834974657

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
    try:
        return data["data"]["user"]["result"]["timeline"]["timeline"]["instructions"], "reposts"
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

DEAD_TOKENS_FILE = os.path.join(tempfile.gettempdir(), "timeline_scrape_dead_tokens")
DEAD_404_GIVEUP = 3

def _token_key(tok):
    return hashlib.sha256(tok.encode()).hexdigest()[:12]

def load_dead_tokens():
    try:
        with open(DEAD_TOKENS_FILE) as f:
            return {line.strip() for line in f if line.strip()}
    except OSError:
        return set()

def save_dead_tokens(keys):
    try:
        with open(DEAD_TOKENS_FILE, "w") as f:
            f.write("\n".join(sorted(keys)) + ("\n" if keys else ""))
    except OSError:
        pass

def next_live_idx(idx, tokens, dead_keys):
    n = len(tokens)
    for step in range(1, n + 1):
        cand = (idx + step) % n
        if _token_key(tokens[cand]) not in dead_keys:
            return cand
    return None

def build_headers(csrf_token, auth_token):
    csrf_token = (SESSION_META.get(auth_token) or {}).get("ct0") or csrf_token
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

def id_to_utc(tid):
    return datetime.fromtimestamp(snowflake_epoch_seconds(tid), timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

def parse_id(value, flag):
    try:
        return int(value)
    except (TypeError, ValueError):
        sys.exit(f"[!] {flag} must be a numeric tweet id, got '{value}'")

def date_to_snowflake(value, flag):
    """Smallest snowflake id that can exist at this (UTC) date/time."""
    if not DATE_RE.match(value):
        sys.exit(f"[!] {flag} value '{value}' doesn't match YYYY-MM-DD[_HH:MM:SS[_UTC]]")
    v = re.sub(r"_UTC$", "", value)
    fmt = "%Y-%m-%d_%H:%M:%S" if "_" in v else "%Y-%m-%d"
    try:
        dt = datetime.strptime(v, fmt).replace(tzinfo=timezone.utc)
    except ValueError as e:
        sys.exit(f"[!] {flag} value '{value}' is not a valid date/time: {e}")
    return (int(dt.timestamp() * 1000) - TWITTER_EPOCH_MS) << 22

def resolve_bounds(since=None, until=None, since_id=None, max_id=None):
    """Collapse --since/--since-id/--until/--max-id into one id range.
    Returns (lower, upper): a tweet is in range when lower < id <= upper
    (None = open on that side). Where a date and an id are both given for the
    same side, the tighter one wins."""
    lowers, uppers = [], []
    if since_id:
        lowers.append(parse_id(since_id, "--since-id"))
    if since:
        lowers.append(date_to_snowflake(since, "--since") - 1)
    if until:
        uppers.append(date_to_snowflake(until, "--until") - 1)
    if max_id:
        uppers.append(parse_id(max_id, "--max-id"))
    lower = max(lowers) if lowers else None
    upper = min(uppers) if uppers else None
    if lower is not None and upper is not None and lower >= upper:
        sys.exit("[!] the since/since-id bound is not older than the until/max-id bound - empty range.")
    return lower, upper

def result_tweet_id(raw):
    """Id of the tweet this timeline result will become in the CSV (same
    unwrapping as extract_row), or None for tombstones/unavailable results."""
    r = unwrap_tweet_result(raw)
    if not r:
        return None
    tid = r.get("rest_id") or (r.get("legacy") or {}).get("id_str")
    try:
        return int(tid)
    except (TypeError, ValueError):
        return None

def get_pinned_ids(data):
    """Ids of pinned-tweet entries (TimelinePinEntry). The pinned tweet is
    served at the top of page 1 whatever its age, so it must not count
    towards the since-boundary check."""
    instructions, _ = get_instructions(data)
    pinned = set()
    for instr in instructions or []:
        if instr.get("type") == "TimelinePinEntry":
            eid = (instr.get("entry") or {}).get("entryId", "")
            if eid.startswith("tweet-") and eid[6:].isdigit():
                pinned.add(int(eid[6:]))
    return pinned

def scrape(user, max_tweets=None, until=None, since=None, max_id=None, since_id=None, no_csv=False, guest=False, retweets=False):
    if guest and not GUEST_BEARER_TOKEN:
        sys.exit("guest bearer_token not provided")
    if not guest and not AUTH_TOKENS:
        sys.exit("No tokens: auth_tokens.txt / sessions.jsonl are empty or missing - add some before running (or pass --guest).")

    lower, upper = resolve_bounds(since=since, until=until, since_id=since_id, max_id=max_id)

    if retweets:
        endpoint_name = "UserRepostsTimeline (--retweets)"
        print(f"[*] --retweets given - scraping @{user}'s reposts only via UserRepostsTimeline.")
    else:
        endpoint_name = "UserTweetsAndReplies"
        print(f"[*] Scraping @{user} via UserTweetsAndReplies "
              f"(feed reaches back ~{TIMELINE_CAP_HINT:,} tweets at most).")
    if lower is not None:
        print(f"[*] Lower bound: keeping tweets from {id_to_utc(lower + 1)} onward (id > {lower}); "
              f"paging stops once that point is reached.")
    if upper is not None:
        print(f"[*] Upper bound: dropping tweets at/after {id_to_utc(upper + 1)} (id > {upper}); "
              f"newer pages are still fetched - the feed can't seek.")

    csrf_token = secrets.token_hex(16)
    query = (
        f"{endpoint_name} for @{user} - client-side range: "
        f"{'id > ' + str(lower) if lower is not None else 'no lower bound'}, "
        f"{'id <= ' + str(upper) if upper is not None else 'no upper bound'}"
    )

    now = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    dest = f"{user}-{now}"
    os.makedirs(dest, exist_ok=True)

    def maybe_build_csv():
        if no_csv:
            return None
        return build_csv(dest, user, lower, upper)

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
            f"  resolved_lower_exclusive_id: {lower if lower is not None else '(none)'}",
            f"  resolved_upper_inclusive_id: {upper if upper is not None else '(none)'}",
            f"  no_csv: {no_csv}",
            f"  endpoint: {endpoint_name}",
            f"  tokens: {len(AUTH_TOKENS)} ({n_susp} suspended)",
        ]
        info_path = os.path.join(dest, "info.txt")
        with open(info_path, "w") as f:
            f.write("\n".join(lines) + "\n")
        return info_path

    session = requests.Session()
    n_susp = 0
    four04 = {}
    if guest:
        tokens_max = 0
        token_idx = 0
        guest_token = get_guest_token(session)
    else:
        tokens_max = len(AUTH_TOKENS) - 1
        token_idx = load_token_idx(len(AUTH_TOKENS))
        suspended_keys = {_token_key(t) for t, m in SESSION_META.items() if m["suspended"]}
        dead_keys = load_dead_tokens() - suspended_keys
        pending_dead = {}
        n_susp = len(suspended_keys & {_token_key(t) for t in AUTH_TOKENS})
        print(f"[*] Token pool: {len(AUTH_TOKENS)} session(s), {n_susp} suspended "
              f"(suspended sessions are used like any other here)")
        if _token_key(AUTH_TOKENS[token_idx]) in dead_keys:
            token_idx = next_live_idx(token_idx, AUTH_TOKENS, dead_keys)
            if token_idx is None:
                sys.exit(f"[!] All tokens are marked dead (delete {DEAD_TOKENS_FILE} to reset) - aborting.")
    count = 0
    pages_fetched = 0
    counter = 0
    consecutive_errors = 0
    stuck_count = 0
    seen_ids = set()
    seen_raw = set()
    boundary_reached = False
    user_id = None
    cursor = None
    exit_status = "completed"
    start = time.time()

    def finish(status, partial=False, check_gap=True):
        nonlocal token_idx
        if not guest:
            token_idx = next_live_idx(token_idx, AUTH_TOKENS, dead_keys) or 0
            save_token_idx(token_idx)
        if check_gap and lower is not None and not boundary_reached:
            print(
                f"[!] Never reached the lower bound (id <= {lower}, {id_to_utc(lower + 1)}) - the feed "
                f"ran out or stopped first (~{TIMELINE_CAP_HINT:,} tweet depth), so there may be a gap "
                f"between this run and your previous data."
            )
        csv_path = maybe_build_csv()
        write_info(status, pages_fetched, csv_path)
        if partial:
            print(f"Partial results: {counter:,} unique tweets from @{user} saved to {dest}/")
        else:
            print(f"[*] All done - completed in {int(time.time() - start)} seconds")
            if lower is not None:
                age = format_duration(time.time() - snowflake_epoch_seconds(lower))
                print(f"Downloaded {counter:,} tweets from @{user} newer than {lower} ({age}) to {dest}/")
            else:
                print(f"Downloaded {counter:,} unique tweets from @{user} to {dest}/")
        return dest

    while True:
        count_next = count + 1
        if guest:
            headers = build_guest_headers(guest_token)
            token_label = f"guest …{guest_token[-4:]}"
        else:
            auth_token = AUTH_TOKENS[token_idx]
            headers = build_headers(csrf_token, auth_token)
            token_label = f"\x1b[1m{token_idx:02d}\x1b[0m {token_tag(auth_token)}…{auth_token[-4:]}"

        if user_id is None:
            user_id = lookup_user_id(session, headers, user)
            if not user_id:
                sys.exit(f"[!] Could not resolve a user id for @{user} via UserByScreenName - aborting.")
            print(f"[*] Resolved @{user} -> user id {user_id}")

        if retweets:
            variables = {
                "userId": user_id,
                "count": 20,
                "includePromotedContent": True,
                "withVoice": True,
            }
            req_url, req_features, req_field_toggles = REPOSTS_URL, REPOSTS_FEATURES, REPOSTS_FIELD_TOGGLES
        else:
            variables = {
                "userId": user_id,
                "count": 20,
                "includePromotedContent": False,
                "includeHasBirdwatchNotes": True,
                "withBirdwatchNotes": True,
                "withCommunity": True,
                "withVoice": True,
                "withV2Timeline": True,
            }
            req_url, req_features, req_field_toggles = TIMELINE_URL, TIMELINE_FEATURES, TIMELINE_FIELD_TOGGLES
        if cursor:
            variables["cursor"] = cursor

        cursor_label = f"…{cursor[-24:]}" if cursor else "(start)"
        print(
            f"page \x1b[40m {count_next} \x1b[0m | elapsed: {int(time.time()-start)}s | "
            f"token: {token_label} | endpoint: {'reposts' if retweets else 'tweets+replies'} | "
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
            body = resp.text[:300].replace("\n", " ")
            print(f"!! non-JSON response (status {resp.status_code}) "
                  f"ct={resp.headers.get('content-type')} len={len(resp.content)} body={body!r}")
            if os.environ.get("TS_DEBUG"):
                print(f"   url={resp.url[:300]}")
                print(f"   resp headers={dict(resp.headers)}")
            with open(out_path, "w") as f:
                f.write(resp.text)
            pages_fetched += 1

            if not guest and resp.status_code == 404:
                key = _token_key(auth_token)
                four04[key] = token_label
                if key in suspended_keys:
                    print(f"[!] 404 on suspended session {token_label} - suspended sessions are fine for "
                          f"this endpoint, not marking it dead")
                else:
                    pending_dead[key] = token_label
                    print(f"[!] 404 on token {token_label} - skipping it")
                if len(four04) >= DEAD_404_GIVEUP:
                    print(
                        f"[!] {len(four04)} different tokens 404'd in a row - this looks like a "
                        f"stale GraphQL query id, not bad sessions. Not marking them dead."
                    )
                    exit_status = "stopped - repeated 404s across tokens"
                    break
                nxt = next_live_idx(token_idx, AUTH_TOKENS, dead_keys | set(four04))
                if nxt is None:
                    print("[!] Every live token 404'd - this looks like a stale GraphQL query id/features. "
                          "Not marking them dead.")
                    exit_status = "stopped - repeated 404s across tokens"
                    break
                token_idx = nxt
                save_token_idx(token_idx)
                continue

            consecutive_errors += 1
            if (not guest and resp.status_code in (401, 403, 429)
                    and consecutive_errors < MAX_CONSECUTIVE_ERRORS):
                token_idx = next_live_idx(token_idx, AUTH_TOKENS, dead_keys) or 0
                save_token_idx(token_idx)
                print(f"   -> rotating to token {token_idx:02d} and retrying")
                time.sleep(min(BACKOFF_BASE * (2 ** (consecutive_errors - 1)), BACKOFF_MAX))
                continue
            exit_status = f"stopped - non-JSON response (status {resp.status_code})"
            break

        with open(out_path, "w") as f:
            json.dump(data, f)
        pages_fetched += 1
        if not guest and pending_dead:
            dead_keys |= set(pending_dead)
            save_dead_tokens(dead_keys)
            print(f"[*] Endpoint responded fine - marked {len(pending_dead)} token(s) dead for future runs: "
                  f"{', '.join(pending_dead.values())}")
            pending_dead.clear()
        four04.clear()

        api_errors = data.get("errors")
        if api_errors:
            consecutive_errors += 1
            print(f"[!] API error on token {token_label} (status {resp.status_code}): {api_errors}")

            if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                print(
                    f"[!] {consecutive_errors} consecutive API errors - giving up "
                    f"(this usually means the backend is down, not a single bad token)."
                )
                return finish(
                    f"partial - {consecutive_errors} consecutive API errors, gave up",
                    partial=True,
                )

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
                token_idx = next_live_idx(token_idx, AUTH_TOKENS, dead_keys) or 0
                save_token_idx(token_idx)
            time.sleep(backoff)
            continue

        consecutive_errors = 0
        entries, layout = get_entries(data)
        tweets = list(iter_tweet_results(entries, layout))
        next_cursor = get_cursor(entries, "Bottom")
        pinned_ids = get_pinned_ids(data)

        if len(tweets) == 0:
            if count_next == 1:
                print(
                    "[!] 0 tweets on the very first page - empty/protected account, bad auth, "
                    "or a stale query id/features (check the saved JSON)."
                )
            print(f"[*] Timeline returned 0 tweets on this page (status {resp.status_code}) - end of feed")
            return finish("completed - reached end of results")

        items = []
        for t in tweets:
            tid = result_tweet_id(t)
            if tid is not None:
                items.append((tid, unwrap_tweet_result(t), tid in pinned_ids))

        shown = [it for it in items if not it[2]] or items
        if shown:
            first_date = ((shown[0][1].get("legacy") or {}).get("created_at") or "").replace(" +0000", "")
            last_date = ((shown[-1][1].get("legacy") or {}).get("created_at") or "").replace(" +0000", "")
        else:
            first_date = last_date = ""
        print(f"\x1b[1;96m{first_date} <----> {last_date}\x1b[0m", end=" | ")

        remaining = print_rate_limits(resp.headers)
        if guest and remaining is not None and remaining <= GUEST_RATE_LIMIT_REFRESH_THRESHOLD:
            print(f"[*] Guest token has {remaining} request(s) left - rotating to a fresh one")
            guest_token = get_guest_token(session, force_refresh=True)

        page_ids = [tid for tid, _, _ in items]
        organic_ids = [tid for tid, _, pinned in items if not pinned]

        hit_lower = lower is not None and any(tid <= lower for tid in organic_ids)
        kept = [tid for tid in page_ids
                if (lower is None or tid > lower) and (upper is None or tid <= upper)]
        skipped_newer = sum(1 for tid in organic_ids if upper is not None and tid > upper)

        new_raw = [tid for tid in page_ids if tid not in seen_raw]
        seen_raw.update(page_ids)
        seen_ids.update(kept)
        counter = len(seen_ids)

        if skipped_newer:
            print(f"    skipped {skipped_newer} tweet(s) newer than the upper bound")

        if hit_lower:
            boundary_reached = True
            print(f"[*] Reached tweets at/before id {lower} ({id_to_utc(lower + 1)}) - stopping here "
                  f"(UserTweetsAndReplies has no server-side filter, so this is enforced client-side).")
            return finish("completed - reached --since/--since-id boundary")

        if max_tweets is not None and counter >= max_tweets:
            return finish("completed - hit --max-tweets", check_gap=False)

        made_progress = bool(new_raw) and next_cursor and next_cursor != cursor
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
                return finish("partial - cursor pagination stalled", partial=True)

        cursor = next_cursor
        if not guest:
            token_idx = next_live_idx(token_idx, AUTH_TOKENS, dead_keys) or 0
            save_token_idx(token_idx)
        count += 1
        time.sleep(INTERVAL)

    return finish(exit_status, partial=True)

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

def screen_name_of(user_result):
    if not user_result:
        return ""
    return (
        user_result.get("core", {}).get("screen_name")
        or user_result.get("legacy", {}).get("screen_name")
        or ""
    )

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
        extras = [full for full in mapping.values() if full not in base]
        if extras:
            base = f"{base} {' '.join(extras)}"

    quoted = result.get("quoted_status_result")
    if quoted:
        qresult = quoted.get("result", {}) or {}
        if qresult.get("__typename") == "TweetWithVisibilityResults":
            qresult = qresult.get("tweet", qresult)
        q_screen_name = screen_name_of(
            qresult.get("core", {}).get("user_results", {}).get("result", {})
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
    screen_name = screen_name_of(
        result.get("core", {}).get("user_results", {}).get("result", {})
    )
    url = f"https://x.com/{screen_name}/status/{tweet_id}" if tweet_id else ""

    return [tweet_id, date, text, replies, retweets, quotes, likes, views, source, birdwatch, conversation_id, url]

def build_csv(dest, user, lower=None, upper=None):
    """Build the CSV from every saved page, keeping only tweets inside the
    lower < id <= upper range (the pages also hold out-of-range tweets from the
    page that crossed the boundary, plus the pinned tweet)."""
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
                if row[0].isdigit():
                    tid = int(row[0])
                    if (lower is not None and tid <= lower) or (upper is not None and tid > upper):
                        continue
                rows[row[0]] = row

    if not rows:
        print(f"No in-range tweets found for @{user} - skipping CSV write.")
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
        next(reader, None)
        for row in reader:
            if row and row[0]:
                last_id = row[0]
    return last_id

def parse_args():
    parser = argparse.ArgumentParser(
        description="Scrape all tweets and replies from a user via X's UserTweetsAndReplies GraphQL "
        "endpoint, paginating with the response cursor. Date/id bounds are enforced client-side."
    )
    parser.add_argument("user", help="username to scrape (without @)")
    parser.add_argument(
        "--max-tweets",
        dest="max_tweets",
        type=int,
        default=None,
        help=(
            "Stop once this many unique in-range tweets are collected. Without it (or a "
            "--since/--since-id/--update bound) the script pages until the endpoint runs out "
            "of tweets (~3200 deep) or every token in AUTH_TOKENS gets rate-limited."
        ),
    )
    parser.add_argument(
        "--until",
        dest="until",
        help=(
            "Drop tweets at/after this date/time (exclusive, UTC). Formats: YYYY-MM-DD, "
            "YYYY-MM-DD_HH:MM:SS, or YYYY-MM-DD_HH:MM:SS_UTC. The feed can't seek, so newer "
            "pages are still fetched and discarded until this point is reached."
        ),
    )
    parser.add_argument(
        "--since",
        dest="since",
        help=(
            "Keep tweets from this date/time onward (inclusive, UTC) and STOP paging once an "
            "older tweet is seen. Same formats as --until."
        ),
    )
    parser.add_argument(
        "--max-id",
        dest="max_id",
        help="Drop tweets newer than this tweet id (inclusive bound). Like --until, newer pages are still fetched.",
    )
    parser.add_argument(
        "--since-id",
        dest="since_id",
        help="Keep only tweets newer than this tweet id (exclusive) and STOP paging once it is reached.",
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
        "--sessions",
        dest="sessions",
        metavar="FILE",
        help=(
            "Nitter-style sessions.jsonl to take auth sessions from (cookie kind: auth_token + ct0). "
            "Merged with auth_tokens.txt. Suspended sessions are used like any other. Defaults to "
            "sessions.jsonl next to the script (or $TWITTER_SESSIONS_FILE) if it exists."
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
            "tweet id from it, and use that as --since-id for this run - paging stops as "
            "soon as it catches up to what you already have. If no prior CSV is found, runs "
            "a normal full scan instead. Ideal for cronjobs. Ignored if --since-id is also "
            "given explicitly."
        ),
    )
    parser.add_argument(
        "--retweets",
        dest="retweets",
        action="store_true",
        help=(
            "Scrape via the UserRepostsTimeline endpoint instead - returns only this user's "
            "reposts (retweets), not their own tweets or replies. All bounds work the same "
            "client-side (pages come back newest-first)."
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

    if not args.guest:
        add_sessions(args.sessions or SESSIONS_FILE, required=bool(args.sessions))

    scrape(
        args.user,
        args.max_tweets,
        until=args.until,
        since=args.since,
        max_id=args.max_id,
        since_id=since_id,
        no_csv=args.no_csv,
        guest=args.guest,
        retweets=args.retweets,
    )
