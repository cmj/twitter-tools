#!/usr/bin/env python3
"""
Extract tweet id, timestamp, text, and engagement stats from an X/Twitter
profile timeline.

RSS is incomplete, mostly a proof-of-concept for now.

Usage:
    python3 extract_tweets.py elonmusk
    python3 extract_tweets.py cnn
    python3 extract_tweets.py nasa --json
    python3 extract_tweets.py nasa --rss > nasa.xml
    python3 extract_tweets.py nasa --stats

    # Parse an HTML file you already saved instead of fetching live:
    python3 extract_tweets.py elonmusk --file saved_page.html
"""
import argparse
import datetime
import json
import re
import sys
import urllib.request
import email.utils as email_utils
from xml.sax.saxutils import escape

_JS_ESCAPE_RE = re.compile(
    r'\\u[dD][89abAB][0-9a-fA-F]{2}\\u[dD][c-fC-F][0-9a-fA-F]{2}'  # surrogate pair
    r'|\\u[0-9a-fA-F]{4}'                                          # \uXXXX
    r'|\\n|\\t|\\r|\\"|\\\\|\\/'                                   # simple escapes
)

_SIMPLE_ESCAPES = {'\\n': '\n', '\\t': '\t', '\\r': '\r', '\\"': '"', '\\\\': '\\', '\\/': '/'}


def _js_unescape_match(m: re.Match) -> str:
    s = m.group(0)
    if s in _SIMPLE_ESCAPES:
        return _SIMPLE_ESCAPES[s]
    if len(s) == 12:
        high = int(s[2:6], 16)
        low = int(s[8:12], 16)
        return chr(0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00))
    return chr(int(s[2:6], 16))


def unescape_js_string(s: str) -> str:
    return _JS_ESCAPE_RE.sub(_js_unescape_match, s)


def fetch_profile_html(account: str) -> str:
    url = f"https://x.com/{account}"
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/128.0.0.0 Safari/537.36"
            ),
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.read().decode("utf-8", errors="replace")


def find_matching_bracket(text: str, start: int) -> int:
    depth = 0
    in_string = False
    escape = False
    i = start
    while i < len(text):
        c = text[i]
        if in_string:
            if escape:
                escape = False
            elif c == '\\':
                escape = True
            elif c == '"':
                in_string = False
        else:
            if c == '"':
                in_string = True
            elif c == '[':
                depth += 1
            elif c == ']':
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def extract_bracket_array(text: str, anchor_re: str, start_pos: int = 0):
    m = re.search(anchor_re, text[start_pos:])
    if not m:
        return None, None
    bracket_pos = start_pos + m.end() - 1  # position of '['
    close_pos = find_matching_bracket(text, bracket_pos)
    if close_pos == -1:
        return None, None
    return text[bracket_pos + 1:close_pos], close_pos + 1


def extract_url_entities(chunk: str, rest_id: str):
    anchor = r'rest_id:\s*"' + re.escape(rest_id) + r'"\s*,\s*url_entities:\s*\$R\[\d+\]\s*=\s*\['
    inner, _ = extract_bracket_array(chunk, anchor)
    if not inner:
        return []
    pairs = []
    for m in re.finditer(
        r'expanded_url:\s*"((?:[^"\\]|\\.)*)"[\s\S]*?url:\s*"((?:[^"\\]|\\.)*)"',
        inner,
    ):
        expanded_url = unescape_js_string(m.group(1))
        short_url = unescape_js_string(m.group(2))
        pairs.append((short_url, expanded_url))
    return pairs


def extract_media_urls(chunk: str):
    inner, _ = extract_bracket_array(chunk, r'media_entities2:\s*\$R\[\d+\]\s*=\s*\[')
    if not inner:
        return []

    items = []
    depth = 0
    in_string = False
    escape = False
    item_start = None
    for i, c in enumerate(inner):
        if in_string:
            if escape:
                escape = False
            elif c == '\\':
                escape = True
            elif c == '"':
                in_string = False
            continue
        if c == '"':
            in_string = True
        elif c == '{':
            if depth == 0:
                item_start = i
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0 and item_start is not None:
                items.append(inner[item_start:i + 1])
                item_start = None

    urls = []
    for item in items:
        type_m = re.search(r'type:\s*"(photo|video|animated_gif)"', item)
        media_type = type_m.group(1) if type_m else None

        if media_type in ("video", "animated_gif"):
            variants_inner, _ = extract_bracket_array(item, r'variants:\s*\$R\[\d+\]\s*=\s*\[')
            best_url, best_bitrate = None, -1
            if variants_inner:
                for vm in re.finditer(
                    r'\{\s*(?:bitrate:\s*(\d+)\s*,\s*)?content_type:\s*"([^"]+)"\s*,\s*url:\s*"([^"]+)"\s*\}',
                    variants_inner,
                ):
                    bitrate = int(vm.group(1)) if vm.group(1) else 0
                    content_type = vm.group(2)
                    variant_url = vm.group(3)
                    if content_type == "video/mp4" and bitrate > best_bitrate:
                        best_url, best_bitrate = variant_url, bitrate
            if best_url:
                urls.append(best_url)
                continue

        url_m = re.search(r'media_url_https:\s*"([^"]+)"', item)
        if url_m:
            urls.append(url_m.group(1))

    return urls


def extract_tweets(html: str):
    scripts = re.findall(r'<script[^>]*>(.*?)</script>', html, re.DOTALL)

    candidates = [s for s in scripts if 'tweet_results' in s and 'full_text' in s]

    results = []
    for s in candidates:
        tweet_iter = list(re.finditer(
            r'(?<![a-zA-Z_])tweet_results:\s*\$R\[\d+\]\s*=\s*\{\s*id:\s*"[^"]+"\s*,\s*rest_id:\s*"(\d+)"',
            s
        ))
        for i, m in enumerate(tweet_iter):
            rest_id = m.group(1)
            start = m.end()
            end = tweet_iter[i + 1].start() if i + 1 < len(tweet_iter) else len(s)
            chunk = s[start:end]

            cm = re.search(r'created_at_ms:\s*(\d+)', chunk)
            fm = re.search(r'full_text:\s*"((?:[^"\\]|\\.)*)"', chunk)

            created_ms = cm.group(1) if cm else None
            text = fm.group(1) if fm else None
            if text:
                text = unescape_js_string(text)

            counts_m = re.search(
                r'counts:\s*\$R\[\d+\]\s*=\s*\{\s*bookmark_count:\s*(\d+)\s*,\s*favorite_count:\s*(\d+)\s*,\s*'
                r'quote_count:\s*(\d+)\s*,\s*reply_count:\s*(\d+)\s*,\s*retweet_count:\s*(\d+)\s*\}',
                chunk,
            )
            reply_count = int(counts_m.group(4)) if counts_m else None
            retweet_count = int(counts_m.group(5)) if counts_m else None
            quote_count = int(counts_m.group(3)) if counts_m else None
            like_count = int(counts_m.group(2)) if counts_m else None
            bookmark_count = int(counts_m.group(1)) if counts_m else None

            views_m = re.search(
                r'rest_id:\s*"' + re.escape(rest_id) + r'"\s*,\s*url_entities:\s*\$R\[\d+\]\s*=\s*\[[\s\S]*?\]\s*,\s*'
                r'views:\s*\$R\[\d+\]\s*=\s*\{\s*count:\s*"(\d+)"\s*\}',
                chunk,
            )
            view_count = int(views_m.group(1)) if views_m else None

            if created_ms and text:
                for short_url, expanded_url in extract_url_entities(chunk, rest_id):
                    text = text.replace(short_url, expanded_url)

                media_urls = extract_media_urls(chunk)
                if media_urls:
                    text = text + " " + " ".join(media_urls)

                ts = datetime.datetime.fromtimestamp(
                    int(created_ms) / 1000, tz=datetime.timezone.utc
                ).strftime('%Y-%m-%d %H:%M:%S UTC')
                results.append({
                    "tweet_id": rest_id,
                    "timestamp": ts,
                    "created_ms": int(created_ms),
                    "text": text,
                    "reply_count": reply_count,
                    "retweet_count": retweet_count,
                    "quote_count": quote_count,
                    "like_count": like_count,
                    "bookmark_count": bookmark_count,
                    "view_count": view_count,
                })

    seen = set()
    deduped = []
    for r in results:
        if r["tweet_id"] not in seen:
            seen.add(r["tweet_id"])
            deduped.append(r)
    return deduped


def format_stats(t: dict) -> str:
    """Format engagement counts as: ↳ replies ⇅ retweets ‟ quotes ♥ likes 🡕 views
    Missing fields (not present in the source payload) are shown as '-'."""
    def fmt(n):
        return f"{n:,}" if isinstance(n, int) else "-"

    return (
        f"↳ {fmt(t.get('reply_count'))} "
        f"⇅ {fmt(t.get('retweet_count'))} "
        f"‟ {fmt(t.get('quote_count'))} "
        f"♥ {fmt(t.get('like_count'))} "
        f"🡕 {fmt(t.get('view_count'))}"
    )


def build_rss(account: str, tweets: list, stats: bool = False) -> str:
    channel_link = f"https://x.com/{account}"
    now = email_utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))

    items = []
    for t in tweets:
        item_link = f"{channel_link}/status/{t['tweet_id']}"
        pub_date = email_utils.format_datetime(
            datetime.datetime.fromtimestamp(t["created_ms"] / 1000, tz=datetime.timezone.utc)
        )
        title = t["text"] if len(t["text"]) <= 80 else t["text"][:77] + "..."
        description = t["text"]
        if stats:
            description = f"{description}\n\n{format_stats(t)}"
        items.append(
            "    <item>\n"
            f"      <title>{escape(title)}</title>\n"
            f"      <link>{escape(item_link)}</link>\n"
            f"      <guid isPermaLink=\"true\">{escape(item_link)}</guid>\n"
            f"      <pubDate>{pub_date}</pubDate>\n"
            f"      <description>{escape(description)}</description>\n"
            "    </item>"
        )

    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<rss version="2.0">\n'
        "  <channel>\n"
        f"    <title>@{escape(account)} on X</title>\n"
        f"    <link>{escape(channel_link)}</link>\n"
        f"    <description>Recent posts from @{escape(account)}</description>\n"
        f"    <lastBuildDate>{now}</lastBuildDate>\n"
        + "\n".join(items) +
        "\n  </channel>\n"
        "</rss>\n"
    )


def main():
    parser = argparse.ArgumentParser(
        description="Extract tweet id, timestamp, text, and stats from an X/Twitter profile."
    )
    parser.add_argument(
        "account",
        help="X/Twitter handle to fetch, without the @ (e.g. elonmusk, cnn, nasa)",
    )
    parser.add_argument(
        "--file",
        help="Parse this local HTML file instead of fetching https://x.com/<account> live",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print results as JSON instead of pipe-delimited text",
    )
    parser.add_argument(
        "--rss",
        action="store_true",
        help="Print results as an RSS 2.0 feed instead of pipe-delimited text",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Include engagement stats (replies, retweets, quotes, likes, "
             "views) — appended as a pipe-delimited field in plain-text "
             "output, or at the bottom of each item's description in --rss",
    )
    args = parser.parse_args()

    if args.json and args.rss:
        parser.error("--json and --rss are mutually exclusive")

    account = args.account.lstrip("@")

    if args.file:
        with open(args.file, "rb") as f:
            html = f.read().decode("utf-8", errors="replace")
    else:
        try:
            html = fetch_profile_html(account)
        except Exception as e:
            print(f"Failed to fetch https://x.com/{account}: {e}", file=sys.stderr)
            sys.exit(1)

    tweets = extract_tweets(html)

    if not tweets:
        print(
            f"No tweets found for @{account}. X's page structure changes often "
            "and may require being logged in / a real browser session (cookies, "
            "JS execution) to render the timeline at all.",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.rss:
        print(build_rss(account, tweets, stats=args.stats))
    elif args.json:
        print(json.dumps(tweets, indent=2))
    else:
        for t in tweets:
            status_url = f"https://x.com/i/status/{t['tweet_id']}"
            line = f'{t["timestamp"]} | {t["text"]}'
            if args.stats:
                line += f' | {format_stats(t)}'
            line += f' | {status_url}'
            print(line)


if __name__ == "__main__":
    main()
