#!/usr/bin/env python3
"""
timeline_create-csv.py

Standalone CSV builder for directories of raw JSON pages saved by
timeline_scrape.py. Useful for regenerating/backfilling CSVs from old
scrape directories without re-hitting the API - e.g. after a format
change to the CSV columns, or if --no-csv was used originally.

Output columns:
Id,Date,Text,Replies,ReTweets,Quotes,Likes,Views,Source,Birdwatch,ConversationId,Url

Usage:
    ./timeline_create-csv.py <dir> [<dir> ...]
    # Merge all unique tweets from @NASA to one master file:
    ./timeline_create-csv.py NASA-*/ -o NASA-master.csv
"""

import argparse
import csv
import glob
import json
import os
import re

def strip_html(s):
    return re.sub(r"<[^>]+>", "", s or "").strip()

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

def get_media_url(media):
    """Full-quality direct media URL for a media entity: highest-res jpg/png
    for photos, highest-bitrate mp4 for videos/gifs."""
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
    """Replace every t.co link in `text` with its full expansion: direct
    jpg/png/mp4 for media, expanded_url for plain links. Returns the
    rewritten text plus the mapping (used to catch links note-tweets omit)."""
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

def build_text(result):
    legacy = result.get("legacy", {}) or {}
    note_tweet = (
        result.get("note_tweet", {}).get("note_tweet_results", {}).get("result", {})
    )
    note_text = note_tweet.get("text")
    base = note_text or legacy.get("full_text", "")
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

def collect_rows(dest):
    """Parse every *.json page in `dest` into {tweet_id: row}, deduped by id
    (last write wins)."""
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
    return rows

def write_csv(rows, csv_path):
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            ["Id", "Date", "Text", "Replies", "ReTweets", "Quotes", "Likes", "Views", "Source", "Birdwatch", "ConversationId", "Url"]
        )
        # ascending, unique by Id
        for tid in sorted(rows.keys(), key=lambda x: int(x) if x.isdigit() else 0):
            writer.writerow(rows[tid])

def build_csv(dest, label):
    rows = collect_rows(dest)

    if not rows:
        print(f"No tweets found in {dest}/ - skipping CSV write.")
        return None

    csv_path = f"{dest.rstrip(os.sep)}.csv"
    write_csv(rows, csv_path)
    print(f"CSV written to {csv_path} ({len(rows)} unique tweets) [{label}]")
    return csv_path

def parse_args():
    parser = argparse.ArgumentParser(
        description="Rebuild CSVs from timeline_scrape.py's raw JSON page directories, "
        "without touching the network. Handy for backfilling old scrape dirs after a "
        "CSV format change, or for dirs that were saved with --no-csv."
    )
    parser.add_argument(
        "dirs",
        nargs="+",
        help="one or more scrape output directories (each full of *.json pages)",
    )
    parser.add_argument(
        "-o", "--merge",
        dest="merge_output",
        metavar="OUTPUT.csv",
        help=(
            "Instead of writing one CSV per directory, merge tweets from all given "
            "directories into a single CSV at this path, deduped by tweet id across "
            "all of them."
        ),
    )
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_args()

    dests = []
    for dest in args.dirs:
        dest = dest.rstrip("/")
        if not os.path.isdir(dest):
            print(f"[!] Skipping {dest} - not a directory.")
            continue
        dests.append(dest)

    if args.merge_output:
        rows = {}
        for dest in dests:
            dest_rows = collect_rows(dest)
            print(f"{dest}/: {len(dest_rows)} tweets")
            rows.update(dest_rows)  # dedup by tweet id across all dirs, last write wins

        if not rows:
            print("No tweets found in any given directory - skipping CSV write.")
        else:
            write_csv(rows, args.merge_output)
            print(f"CSV written to {args.merge_output} ({len(rows)} unique tweets, merged from {len(dests)} dirs)")
    else:
        for dest in dests:
            build_csv(dest, label=os.path.basename(dest))
