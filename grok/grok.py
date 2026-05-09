#!/usr/bin/env python3
"""
grok.py - Grok chat

Usage:
  grok.py "your question"
  grok.py -s "quick question"   # short answer mode
  grok.py reset                 # start a new conversation
  grok.py -h                    # show help
"""

import argparse
import json
import os
import re
import secrets
import subprocess
import sys
from pathlib import Path

CONV_ID_FILE = Path("/tmp/grok-py-convId")
BEARER_TOKEN = (
    "AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
)
GROK_MODEL = "grok-3"

def load_env(path: str = "~/.env-twitter") -> dict:
    env = {}
    p = Path(path).expanduser()
    if p.exists():
        for line in p.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                env[k.strip()] = v.strip().strip('"').strip("'")
    return env

def random_ct0() -> str:
    return secrets.token_hex(16)

def make_headers(auth_token: str, ct0: str) -> dict:
    return {
        "Authorization": f"Bearer {BEARER_TOKEN}",
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:146.0) Gecko/20100101 Firefox/146.0",
        "X-Csrf-Token": ct0,
        "Cookie": f"ct0={ct0}; auth_token={auth_token}",
        "Content-Type": "application/json",
    }

def conversation_new(headers: dict) -> str:
    import urllib.request

    query_id = "vvC5uy7pWWHXS2aDi1FZeA"
    url = f"https://x.com/i/api/graphql/{query_id}/CreateGrokConversation"
    payload = json.dumps({"variables": {}, "queryId": query_id}).encode()

    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())

    conv_id = data["data"]["create_grok_conversation"]["conversation_id"]
    CONV_ID_FILE.write_text(conv_id)
    return conv_id

def get_conversation_id(headers: dict) -> str:
    if CONV_ID_FILE.exists():
        cid = CONV_ID_FILE.read_text().strip()
        if cid:
            return cid
    return conversation_new(headers)

def send_message(query: str, conv_id: str, headers: dict) -> dict:
    import urllib.request

    url = "https://grok.x.com/2/grok/add_response.json"
    payload = json.dumps({
        "responses": [
            {
                "message": query,
                "sender": 1,
                "promptSource": "",
                "fileAttachments": [],
            }
        ],
        "systemPromptName": "",
        "grokModelOptionId": GROK_MODEL,
        "conversationId": conv_id,
        "returnSearchResults": False,
        "returnCitations": False,
        "promptMetadata": {"promptSource": "NATURAL", "action": "INPUT"},
        "imageGenerationCount": 4,
        "requestFeatures": {"eagerTweets": False, "serverHistory": False},
    }).encode()

    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
    with urllib.request.urlopen(req) as resp:
        raw = resp.read().decode()

    return raw

def clean_grok_xml(text: str) -> str:
    """Remove <grok:...> XML tags (incl. nested content) without touching URLs."""
    # Full blocks: <grok:tag ...>...</grok:tag>
    text = re.sub(r"<grok:[^>]*>.*?</grok:[^>]*>", "", text, flags=re.DOTALL)
    # Any remaining bare open/close grok tags
    text = re.sub(r"</?grok:[^>]*>", "", text)
    return text


def strip_markdown(text: str) -> str:
    """Strip markdown syntax for plain-text short output."""
    text = re.sub(r"\*{1,3}([^*]+)\*{1,3}", r"\1", text)   # bold/italic *
    text = re.sub(r"_{1,2}([^_]+)_{1,2}", r"\1", text)        # bold/italic _
    text = re.sub(r"`{1,3}[^`]*`{1,3}", "", text)              # code
    text = re.sub(r"^#{1,6}\s+", "", text, flags=re.MULTILINE) # headings
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text) # [label](url) → label
    text = re.sub(r"^\s*[-*+]\s+", "  ", text, flags=re.MULTILINE)  # bullets
    text = re.sub(r"^\s*\d+\.\s+", "  ", text, flags=re.MULTILINE) # numbered lists
    text = re.sub(r"^>{1,}\s?", "", text, flags=re.MULTILINE)  # blockquotes
    text = re.sub(r"^[-*_]{3,}\s*$", "", text, flags=re.MULTILINE) # hr
    return text.strip()


def extract_message(raw: str, debug: bool = False) -> str:
    """
    The API returns newline-delimited JSON objects.
    Collect all final/non-thinking message chunks and join them.
    """
    if debug:
        print("=== raw response ===", file=sys.stderr)
        for i, line in enumerate(raw.splitlines()):
            print(f"  [{i}] {line[:200]}", file=sys.stderr)
        print("=== end raw ===", file=sys.stderr)

    parts = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue

        result = obj.get("result", {})

        if result.get("postIds") is not None:
            continue
        if result.get("cardAttachment") is not None:
            continue
        if result.get("isThinking") is True:
            continue
        msg = result.get("message")
        if not msg:
            continue
        tag = result.get("messageTag")
        if tag is not None and tag != "final":
            continue

        parts.append(msg)

    deduped = []
    for part in parts:
        if deduped and part.startswith(deduped[-1]):
            deduped[-1] = part
        else:
            deduped.append(part)

    text = "".join(deduped)
    text = clean_grok_xml(text)
    text = re.sub(r"Short answer:\s*", "", text)
    return text.strip()

def print_markdown(text: str) -> None:
    """Render markdown with rich if available, else plain."""
    try:
        from rich.console import Console
        from rich.markdown import Markdown

        console = Console()
        console.print(Markdown(text))
    except ImportError:
        plain = re.sub(r"\*{1,2}([^*]+)\*{1,2}", r"\1", text)
        print(plain)

def print_plain(text: str) -> None:
    print(strip_markdown(text))

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="grok",
        description="Grok chat.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  grok "What is the capital of France?"
  grok -s "tldr: what is recursion"
  grok reset          start a fresh conversation
        """,
    )
    parser.add_argument(
        "-s", "--short",
        action="store_true",
        help="Request a short answer and skip markdown rendering",
    )
    parser.add_argument(
        "--env",
        default="~/.env-twitter",
        metavar="FILE",
        help="Path to env file containing auth_token (default: ~/.env-twitter)",
    )
    parser.add_argument(
        "query",
        nargs="+",
        help='Your question, or "reset" to start a new conversation',
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Dump raw API response to stderr for troubleshooting",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    input_text = " ".join(args.query)

    # reset
    if input_text.strip().lower() == "reset":
        env = load_env(args.env)
        auth_token = env.get("auth_token") or os.environ.get("auth_token", "")
        if not auth_token:
            sys.exit("Error: auth_token not found. Set it in ~/.env-twitter or $auth_token.")
        ct0 = random_ct0()
        headers = make_headers(auth_token, ct0)
        cid = conversation_new(headers)
        print(f"Conversation reset. New ID: {cid}")
        return

    # auth
    env = load_env(args.env)
    auth_token = env.get("auth_token") or os.environ.get("auth_token", "")
    if not auth_token:
        sys.exit("Error: auth_token not found. Set it in ~/.env-twitter or $auth_token.")

    ct0 = random_ct0()
    headers = make_headers(auth_token, ct0)

    query = input_text
    if args.short:
        query = f"short answer only. {query}"

    conv_id = get_conversation_id(headers)

    try:
        raw = send_message(query, conv_id, headers)
    except Exception as e:
        sys.exit(f"Request failed: {e}")

    message = extract_message(raw, debug=args.debug)
    if not message:
        sys.exit("No message returned. Check your auth_token or try `grok reset`.")

    if args.short:
        print_plain(message)
    else:
        print_markdown(message)


if __name__ == "__main__":
    main()
