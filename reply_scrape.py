#!/usr/bin/env python3
"""
reply_scrape.py

Grab every reply to one or more tweets via TweetDetail until the thread is exhausted
(or --max-tweets is hit). Companion to timeline_scrape.py, and reuses its
auth-token rotation, header building, and row/CSV extraction - keep both
files in the same directory (and the same auth_tokens.txt next to them).

CSV with the same columns as timeline_scrape.py:
Id,Date,Text,Replies,ReTweets,Quotes,Likes,Views,Source,Birdwatch,ConversationId,Url
Only replies are included - the focal tweet itself and any ancestor tweets
above it in the thread are skipped.

*** Grabbing replies to replies consists of a seperate call to each reply, this can
    be exhausting on large threads. Best practice is using max-depth:
        ./reply_scrape.py <tweet_id> --max-depth 0

Usage:
    ./reply_scrape.py <tweet_id> [<tweet_id> ...] [--max-tweets N] [--ranking {Likes,Relevance,Recency}] [--no-csv]
"""

import argparse
import csv
import json
import os
import secrets
import sys
import time
from collections import deque
from datetime import datetime

import timeline_scrape as ts  # same directory - auth tokens, headers, row extraction

TWEET_DETAIL_URL = "https://x.com/i/api/graphql/XMOz5h24KAZ86qKffKTLdQ/TweetDetail"

FEATURES = {
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
    "responsive_web_grok_image_annotation_enabled": True,
    "responsive_web_grok_imagine_annotation_enabled": True,
    "responsive_web_grok_community_note_auto_translation_is_enabled": True,
    "responsive_web_enhance_cards_enabled": False,
}

FIELD_TOGGLES = {
    "withArticleRichContentState": True,
    "withArticlePlainText": False,
    "withArticleSummaryText": True,
    "withArticleVoiceOver": True,
    "withGrokAnalyze": False,
    "withDisallowedReplyControls": False,
}

INTERVAL = 0      # sleep n seconds between successful requests
STUCK_GIVEUP = 2  # give up on a ranking mode after this many pages in a row with no new tweets / no cursor advance
                  # (separate from timeline_scrape.py's own STUCK_GIVEUP so changing it here doesn't affect that script)


def get_entries(data):
    try:
        instructions = data["data"]["threaded_conversation_with_injections_v2"]["instructions"]
    except (KeyError, TypeError):
        return []
    entries = []
    for instr in instructions or []:
        entries.extend(instr.get("entries", []) or [])
    return entries


def iter_reply_results(entries, focal_id):
    has_focal_marker = any(e.get("entryId", "") == f"tweet-{focal_id}" for e in entries)
    seen_focal = not has_focal_marker
    for e in entries:
        entry_id = e.get("entryId", "")
        content = e.get("content", {}) or {}
        if entry_id == f"tweet-{focal_id}":
            seen_focal = True
            continue
        if not seen_focal:
            continue
        if entry_id.startswith("conversationthread-"):
            for item in content.get("items", []) or []:
                tr = item.get("item", {}).get("itemContent", {}).get("tweet_results")
                if tr:
                    yield tr.get("result")
        elif entry_id.startswith("tweet-"):
            tr = content.get("itemContent", {}).get("tweet_results")
            if tr:
                yield tr.get("result")


def get_cursor(entries, cursor_type="Bottom"):
    for e in entries:
        content = e.get("content", {}) or {}
        if content.get("cursorType") == cursor_type:
            return content.get("value")
    return None


def build_replies_csv(dest, page_records):
    rows = {}
    for fp, focal_id in page_records:
        with open(fp) as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                continue
        entries = get_entries(data)
        for raw_result in iter_reply_results(entries, focal_id):
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
        print(f"No replies found - skipping CSV write.")
        return None

    csv_path = f"{dest}.csv"
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            ["Id", "Date", "Text", "Replies", "ReTweets", "Quotes", "Likes", "Views", "Source", "Birdwatch", "ConversationId", "Url"]
        )
        for tid in sorted(rows.keys(), key=lambda x: int(x) if x.isdigit() else 0):
            writer.writerow(rows[tid])

    print(f"CSV written to {csv_path} ({len(rows)} unique replies)")
    return csv_path


def _paginate_one_mode(focal_id, ranking, dest, session, token_idx, tokens_max,
                        csrf_token, seen_ids, local_ids, max_tweets, page_counter,
                        page_records, start, guest=False, guest_state=None):
    consecutive_errors = 0
    stuck_count = 0
    cursor = None

    while True:
        page_counter[0] += 1
        if guest:
            headers = ts.build_guest_headers(guest_state["token"])
            token_label = f"guest …{guest_state['token'][-4:]}"
        else:
            auth_token = ts.AUTH_TOKENS[token_idx]
            headers = ts.build_headers(csrf_token, auth_token)
            token_label = f"\x1b[1m{token_idx:02d}\x1b[0m …{auth_token[-4:]}"

        variables = {
            "focalTweetId": focal_id,
            "with_rux_injections": False,
            "rankingMode": ranking,
            "includePromotedContent": True,
            "withCommunity": True,
            "withQuickPromoteEligibilityTweetFields": True,
            "withBirdwatchNotes": True,
            "withVoice": True,
        }
        if cursor:
            variables["cursor"] = cursor

        cursor_label = f"…{cursor[-24:]}" if cursor else "(start)"
        print(
            f"[{ranking}] page \x1b[40m {page_counter[0]} \x1b[0m | elapsed: {int(time.time()-start)}s | "
            f"token: {token_label} | tweet: {focal_id} | cursor: {cursor_label} | total replies: {len(seen_ids)}"
        )

        req_params = {
            "variables": json.dumps(variables, separators=(",", ":")),
            "features": json.dumps(FEATURES, separators=(",", ":")),
            "fieldToggles": json.dumps(FIELD_TOGGLES, separators=(",", ":")),
        }

        resp = session.get(TWEET_DETAIL_URL, headers=headers, params=req_params)

        out_path = os.path.join(dest, f"{focal_id}-{ranking.lower()}-{page_counter[0]}.json")

        # Treat any non-200 (e.g. a 429 rate limit) the same as an API error
        # in the body - rotate token and retry rather than assuming JSON.
        if resp.status_code != 200:
            consecutive_errors += 1
            print(f"[!] HTTP {resp.status_code} on token {token_label}")
            with open(out_path, "w") as f:
                f.write(resp.text)
            if consecutive_errors >= ts.MAX_CONSECUTIVE_ERRORS:
                print(f"[!] {consecutive_errors} consecutive errors - giving up on {ranking} mode for {focal_id}.")
                return token_idx, False
            backoff = min(ts.BACKOFF_BASE * (2 ** (consecutive_errors - 1)), ts.BACKOFF_MAX)
            if guest:
                print(f"   -> refreshing guest token, retrying in {backoff}s "
                      f"({consecutive_errors}/{ts.MAX_CONSECUTIVE_ERRORS} consecutive errors)")
                guest_state["token"] = ts.get_guest_token(session, force_refresh=True)
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
            print(f"!! non-JSON response (status {resp.status_code}), saving raw and stopping this mode")
            with open(out_path, "w") as f:
                f.write(resp.text)
            return token_idx, False

        with open(out_path, "w") as f:
            json.dump(data, f)
        page_records.append((out_path, focal_id))

        api_errors = data.get("errors")
        if api_errors:
            consecutive_errors += 1
            print(f"[!] API error on token {token_label} (status {resp.status_code}): {api_errors}")

            if consecutive_errors >= ts.MAX_CONSECUTIVE_ERRORS:
                print(f"[!] {consecutive_errors} consecutive API errors - giving up on {ranking} mode for {focal_id}.")
                return token_idx, False

            backoff = min(ts.BACKOFF_BASE * (2 ** (consecutive_errors - 1)), ts.BACKOFF_MAX)
            if guest:
                print(f"   -> refreshing guest token, retrying in {backoff}s "
                      f"({consecutive_errors}/{ts.MAX_CONSECUTIVE_ERRORS} consecutive errors)")
                guest_state["token"] = ts.get_guest_token(session, force_refresh=True)
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
            guest_state["token"] = ts.get_guest_token(session, force_refresh=True)

        entries = get_entries(data)
        replies = list(iter_reply_results(entries, focal_id))
        next_cursor = get_cursor(entries, "Bottom")

        page_ids = []
        for t in replies:
            result = ts.unwrap_tweet_result(t)
            rid = (result or {}).get("rest_id")
            if rid is not None:
                try:
                    page_ids.append(int(rid))
                except ValueError:
                    pass

        is_first_page = cursor is None
        local_ids.update(page_ids)
        new_ids = [pid for pid in page_ids if pid not in seen_ids]
        seen_ids.update(page_ids)

        if max_tweets is not None and len(seen_ids) >= max_tweets:
            print(f"[*] max-tweets reached during {ranking} mode.")
            return token_idx, True

        if is_first_page and not page_ids:
            print(f"[*] No replies at all for {focal_id} under {ranking} - skipping.")
            if not guest:
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                ts.save_token_idx(token_idx)
            return token_idx, False

        if not next_cursor:
            print(f"[*] No further cursor in {ranking} mode - exhausted.")
            if not guest:
                token_idx = token_idx + 1 if token_idx < tokens_max else 0
                ts.save_token_idx(token_idx)
            return token_idx, False

        made_progress = bool(new_ids) and next_cursor != cursor
        if made_progress:
            stuck_count = 0
        else:
            stuck_count += 1
            print(f"[!] No new replies / cursor didn't advance in {ranking} mode "
                  f"({stuck_count}/{STUCK_GIVEUP} stuck pages)")
            if stuck_count >= STUCK_GIVEUP:
                print(f"\u2717 {ranking} mode stalled for {focal_id} - moving on.")
                if not guest:
                    token_idx = token_idx + 1 if token_idx < tokens_max else 0
                    ts.save_token_idx(token_idx)
                return token_idx, False

        cursor = next_cursor
        if not guest:
            token_idx = token_idx + 1 if token_idx < tokens_max else 0
            ts.save_token_idx(token_idx)
        time.sleep(INTERVAL)


def scrape_replies(root_id, max_tweets=None, rankings=None, no_csv=False, max_depth=6, guest=False):
    if guest and not ts.GUEST_BEARER_TOKEN:
        sys.exit("guest bearer_token not provided - fill in GUEST_BEARER_TOKEN in timeline_scrape.py.")
    if not guest and not ts.AUTH_TOKENS:
        sys.exit("AUTH_TOKENS / auth_tokens.txt is empty - populate the list before running (or pass --guest).")

    rankings = rankings or ["Likes", "Relevance", "Recency"]

    csrf_token = secrets.token_hex(16)
    now = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    dest = f"{root_id}-{now}"
    os.makedirs(dest, exist_ok=True)

    session = ts.requests.Session()
    guest_state = None
    if guest:
        tokens_max = 0
        token_idx = 0
        guest_state = {"token": ts.get_guest_token(session)}
    else:
        tokens_max = len(ts.AUTH_TOKENS) - 1
        token_idx = ts.load_token_idx(len(ts.AUTH_TOKENS))

    seen_ids = set()          # every reply id found anywhere in the tree
    page_records = []         # (file_path, focal_id) for every page saved
    page_counter = [0]
    start = time.time()

    queue = deque([(root_id, 0)])
    visited_as_focal = {root_id}
    hit_max = False

    while queue and not hit_max:
        focal_id, depth = queue.popleft()
        print(f"\n=== depth {depth} | crawling replies to {focal_id} "
              f"| {len(seen_ids):,} found so far | queue: {len(queue)} ===")

        local_ids = set()
        for ranking in rankings:
            token_idx, hit_max = _paginate_one_mode(
                focal_id, ranking, dest, session, token_idx, tokens_max,
                csrf_token, seen_ids, local_ids, max_tweets, page_counter,
                page_records, start, guest=guest, guest_state=guest_state,
            )
            if hit_max:
                break

        if hit_max:
            print(f"[*] max-tweets ({max_tweets}) reached - stopping the crawl.")
            break

        if max_depth is not None and depth >= max_depth:
            continue  # don't expand further down this branch

        for child_id in local_ids:
            child_str = str(child_id)
            if child_str not in visited_as_focal:
                visited_as_focal.add(child_str)
                queue.append((child_str, depth + 1))

    csv_path = None if no_csv else build_replies_csv(dest, page_records)
    print(f"\n[*] Done in {int(time.time()-start)}s - {len(seen_ids):,} unique replies across the whole "
          f"thread under {root_id} saved to {dest}/")
    return dest


def parse_args():
    parser = argparse.ArgumentParser(
        description="Scrape all replies to one or more tweets via X's TweetDetail GraphQL endpoint, "
        "paginating with the response cursor."
    )
    parser.add_argument("tweet_ids", nargs="+", help="one or more tweet ids to fetch replies for")
    parser.add_argument(
        "--max-tweets",
        dest="max_tweets",
        type=int,
        default=None,
        help="Stop once this many unique replies are collected across the WHOLE reply tree for a given "
        "root tweet id (not per-level). Without it, the crawl runs until the tree is exhausted.",
    )
    parser.add_argument(
        "--max-depth",
        dest="max_depth",
        type=int,
        default=6,
        help="How many levels of replies-to-replies to crawl beneath the root tweet (default: 6). "
        "0 fetches only direct replies to the root, matching the old single-level behavior.",
    )
    parser.add_argument(
        "--ranking",
        dest="ranking",
        default=None,
        choices=["Likes", "Relevance", "Recency"],
        help="Force a single rankingMode instead of the default behavior, which cycles through "
        "Likes, Relevance, and Recency and merges the results - each mode surfaces a different "
        "slice of the conversation, since TweetDetail caps how much any one mode will serve.",
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
    rankings = [args.ranking] if args.ranking else None
    for tid in args.tweet_ids:
        scrape_replies(tid, max_tweets=args.max_tweets, rankings=rankings,
                        no_csv=args.no_csv, max_depth=args.max_depth, guest=args.guest)
