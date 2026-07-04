#!/usr/bin/env python3
"""
grok.py - Grok AI CLI with conversation threading and Markdown output

Config file:  ~/.config/grok/config     (auth_token, x_csrf_token, one per line: KEY=VALUE)
Conv state:   ~/.config/grok/convs/NAME.json

Usage:
  grok.py [options] QUERY...
  grok.py --new              use alone to reset; start fresh conversation on current slot
  grok.py --list             list all named conversation slots
  grok.py --conv NAME        use/create named conversation slot (default: main)
  grok.py --short            short answer only (plain text, no Markdown, faster response)
  grok.py --md               always emit Markdown even in --short mode
  grok.py --save             save raw NDJSON .json to LOGS_DIR (default "~/.local/state/grok/logs")
  grok.py --model MODEL      override model (default: grok-4 (may not work)) 
  grok.py --search           enable web search results
  grok.py --citations        enable citations in response
  grok.py --rentry           upload Markdown to rentry.co (url and edit code are printed, not stored/reused)
"""

import argparse
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.cookies import SimpleCookie
from pathlib import Path

BEARER_TOKEN = (
    "AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4"
    "%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
)
CREATE_CONV_QUERY_ID = "vvC5uy7pWWHXS2aDi1FZeA"
ADD_RESPONSE_URL     = "https://grok.x.com/2/grok/add_response.json"
CREATE_CONV_URL      = (
    f"https://x.com/i/api/graphql/{CREATE_CONV_QUERY_ID}/CreateGrokConversation"
)
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64; rv:146.0) Gecko/20100101 Firefox/146.0"
)
CONFIG_DIR  = Path("~/.config/grok").expanduser()
CONFIG_FILE = CONFIG_DIR / "config"
CONVS_DIR   = CONFIG_DIR / "convs"
#LOGS_DIR    = CONFIG_DIR / "logs"
LOGS_DIR    = Path("~/.local/state/grok/logs").expanduser()

RENTRY_BASE = "https://rentry.co"

def load_config() -> dict:
    cfg = {}
    if CONFIG_FILE.exists():
        for line in CONFIG_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                k, v = k.strip(), v.strip()
                # strip optional surrounding quotes
                if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
                    v = v[1:-1]
                cfg[k] = v
    # env overrides
    for key in ("AUTH_TOKEN", "X_CSRF_TOKEN"):
        if key in os.environ:
            cfg[key.lower()] = os.environ[key]
    return cfg

def cfg_bool(cfg: dict, key: str, default: bool) -> bool:
    if key not in cfg:
        return default
    return cfg[key].strip().lower() in ("1", "true", "yes", "on")

def conv_path(name: str) -> Path:
    CONVS_DIR.mkdir(parents=True, exist_ok=True)
    return CONVS_DIR / f"{name}.json"

def load_conv(name: str) -> dict:
    p = conv_path(name)
    if p.exists():
        return json.loads(p.read_text())
    return {}

def save_conv(name: str, data: dict):
    conv_path(name).write_text(json.dumps(data, indent=2))

def append_turn(name: str, query: str, reply: str):
    state = load_conv(name)
    if not state:
        return
    turns = state.setdefault("turns", [])
    turns.append({
        "ts":     int(time.time()),
        "query":  query,
        "reply":  reply,
    })
    save_conv(name, state)

def archive_current(state: dict) -> dict:
    """
    Move the currently-active conversation (id/created/turns) of a slot's
    state into its archive list. Returns the updated state. No-op if there's
    no active id yet (fresh/empty slot).
    """
    if not state.get("id"):
        return state
    archive = state.setdefault("archive", [])
    archive.append({
        "id":      state["id"],
        "created": state.get("created", 0),
        "retired": int(time.time()),
        "turns":   state.get("turns", []),
    })
    return state

def find_conv_id(target_id: str):
    """
    Search all slots for target_id, whether it's the currently active id or
    sitting in a slot's archive. Returns (slot_name, location, entry) where
    location is 'active' or 'archive', or (None, None, None) if not found.
    """
    CONVS_DIR.mkdir(parents=True, exist_ok=True)
    for p in sorted(CONVS_DIR.glob("*.json")):
        try:
            state = json.loads(p.read_text())
        except Exception:
            continue
        if state.get("id") == target_id:
            return p.stem, "active", state
        for entry in state.get("archive", []):
            if entry.get("id") == target_id:
                return p.stem, "archive", entry
    return None, None, None

def use_conv_id(conv_name: str, target_id: str):
    """
    Make target_id the active conversation on conv_name, archiving whatever
    was previously active on that slot. target_id can currently be active
    elsewhere (still works, just adopts it) or sitting in any slot's archive.
    """
    src_slot, location, entry = find_conv_id(target_id)
    if src_slot is None:
        print(f"No conversation found with id: {target_id}", file=sys.stderr)
        sys.exit(1)

    picked = {
        "id":      entry["id"],
        "created": entry.get("created", 0),
        "turns":   entry.get("turns", []),
    }

    if location == "archive":
        src_state = load_conv(src_slot)
        src_state["archive"] = [
            e for e in src_state.get("archive", []) if e.get("id") != target_id
        ]
        save_conv(src_slot, src_state)

    if location == "active" and src_slot != conv_name:
        src_state = load_conv(src_slot)
        src_state.pop("id", None)
        src_state.pop("created", None)
        src_state["turns"] = []
        save_conv(src_slot, src_state)

    dest_state = load_conv(conv_name)
    if not dest_state:
        dest_state = {"name": conv_name}
    dest_state = archive_current(dest_state)
    dest_state["id"]        = picked["id"]
    dest_state["created"]   = picked["created"]
    dest_state["last_used"] = int(time.time())
    dest_state["turns"]     = picked["turns"]
    save_conv(conv_name, dest_state)

    print(f"[switched {conv_name} -> {picked['id']} "
          f"(from {src_slot}'s {location})]", file=sys.stderr)

def list_convs():
    CONVS_DIR.mkdir(parents=True, exist_ok=True)
    convs = sorted(CONVS_DIR.glob("*.json"))
    if not convs:
        print("No conversation slots found.")
        return
    print(f"{'SLOT':<20} {'CONVERSATION ID':<25} LAST USED")
    for p in convs:
        try:
            d = json.loads(p.read_text())
            ts = time.strftime("%Y-%m-%d %H:%M", time.localtime(d.get("last_used", 0)))
            print(f"{p.stem:<20} {d.get('id','?'):<25} {ts}")
        except Exception:
            print(f"{p.stem:<20} (unreadable)")

def clip(text: str, n_words: int = 10) -> str:
    text = " ".join(text.split())  # collapse whitespace/newlines
    words = text.split(" ")
    out = " ".join(words[:n_words])
    if len(words) > n_words:
        out += "..."
    return out

def show_history(conv_name: str = None):
    CONVS_DIR.mkdir(parents=True, exist_ok=True)
    convs = sorted(CONVS_DIR.glob("*.json"))
    if not convs:
        print("No conversation slots found.")
        return

    if conv_name:
        convs = [p for p in convs if p.stem == conv_name]
        if not convs:
            print(f"No such conversation slot: {conv_name}")
            return

    def print_turns(turns):
        if not turns:
            print("  (no recorded turns)")
            return
        for t in turns:
            ts = time.strftime("%Y-%m-%d %H:%M", time.localtime(t.get("ts", 0)))
            q  = clip(t.get("query", ""))
            print(f"  [{ts}] {q}")

    for p in convs:
        try:
            d = json.loads(p.read_text())
        except Exception:
            print(f"{p.stem}: (unreadable)")
            continue

        print(f"=== {p.stem}  [active: {d.get('id', '(none)')}] ===")
        print_turns(d.get("turns", []))

        archive = d.get("archive", [])
        if archive:
            for entry in reversed(archive):  # most recently retired first
                retired_ts = time.strftime(
                    "%Y-%m-%d %H:%M", time.localtime(entry.get("retired", 0))
                )
                print(f"  --- archived [{entry.get('id', '?')}] (retired {retired_ts}) ---")
                print_turns(entry.get("turns", []))
        print()

def make_headers(auth_token: str, csrf_token: str) -> dict:
    return {
        "Authorization":  f"Bearer {BEARER_TOKEN}",
        "User-Agent":     USER_AGENT,
        "X-Csrf-Token":   csrf_token,
        "Cookie":         f"ct0={csrf_token}; auth_token={auth_token}",
        "Content-Type":   "application/json",
    }

def http_post(url: str, headers: dict, payload: dict) -> bytes:
    data = json.dumps(payload).encode()
    req  = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()

def new_conversation(headers: dict, conv_name: str) -> str:
    payload = {"variables": {}, "queryId": CREATE_CONV_QUERY_ID}
    raw = http_post(CREATE_CONV_URL, headers, payload)
    data = json.loads(raw)
    conv_id = data["data"]["create_grok_conversation"]["conversation_id"]

    state = load_conv(conv_name)
    if not state:
        state = {"name": conv_name}
    state = archive_current(state)  # preserve old id/turns before overwrite

    state["id"]        = conv_id
    state["created"]   = int(time.time())
    state["last_used"] = int(time.time())
    state["name"]       = conv_name
    state["turns"]      = []
    save_conv(conv_name, state)
    return conv_id

def get_or_create_conv(headers: dict, conv_name: str, force_new: bool) -> str:
    state = load_conv(conv_name)
    if force_new or not state.get("id"):
        conv_id = new_conversation(headers, conv_name)
        print(f"[new conversation: {conv_name} / {conv_id}]", file=sys.stderr)
        return conv_id
    # update last_used timestamp
    state["last_used"] = int(time.time())
    save_conv(conv_name, state)
    return state["id"]

class RentryClient:
    """Minimal rentry.co API client (cookie-based CSRF, form-encoded POST)."""

    def __init__(self):
        self.cookie_jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.cookie_jar)
        )

    def _get(self, url: str) -> "urllib.response.addinfourl":
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        return self.opener.open(req, timeout=30)

    def _post(self, url: str, data: dict, csrftoken: str) -> dict:
        body = urllib.parse.urlencode(data).encode()
        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "User-Agent": USER_AGENT,
                "Referer": RENTRY_BASE + "/",
                "Origin": RENTRY_BASE,
                "Content-Type": "application/x-www-form-urlencoded",
                "X-CSRFToken": csrftoken,
            },
            method="POST",
        )
        with self.opener.open(req, timeout=30) as resp:
            raw = resp.read().decode()
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            raise RuntimeError(f"non-JSON response from rentry.co: {raw[:300]!r}")

    def _csrf_token(self) -> str:
        resp = self._get(RENTRY_BASE + "/")
        resp.read()  # ensure Set-Cookie processed
        for cookie in self.cookie_jar:
            if cookie.name == "csrftoken":
                return cookie.value
        raise RuntimeError("Could not obtain rentry.co csrf token")

    def new(self, text: str, edit_code: str = "") -> dict:
        if not text or not text.strip():
            raise RuntimeError("refusing to publish empty text")
        csrftoken = self._csrf_token()
        payload = {
            "csrfmiddlewaretoken": csrftoken,
            "url": "",
            "edit_code": edit_code,
            "text": text,
        }
        return self._post(f"{RENTRY_BASE}/api/new", payload, csrftoken)

def rentry_publish(text: str) -> str:
    """
    Create a new rentry.co paste (random url). Prints the url and edit code
    for the user's own reference, the tool does not track or reuse them.
    """
    client = RentryClient()

    resp = client.new(text)
    if resp.get("status") != "200":
        content = resp.get("content")
        detail = content
        if isinstance(content, dict) and content.get("errors"):
            detail = content["errors"]
        raise RuntimeError(f"rentry.co error: {detail}  (full response: {resp})")

    page_url  = resp["url"]
    edit_code = resp["edit_code"]

    page_url = page_url.rstrip("/").rsplit("/", 1)[-1]
    page_url = page_url.replace("https:", "").replace("http:", "").strip("/")

    full_url = f"https://rentry.co/{page_url}"
    print(f"rentry: {full_url}")
    print(f"edit code: {edit_code}")
    return full_url

def extract_message(ndjson_text: str) -> str:
    """Assemble final message chunks from NDJSON streaming response."""
    chunks = []
    for line in ndjson_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        r = obj.get("result", {})
        if r.get("postIds") is not None:
            continue
        msg      = r.get("message", "")
        tag      = r.get("messageTag", "")
        thinking = r.get("isThinking", False)
        card     = r.get("cardAttachment")
        if not msg:
            continue
        if tag == "final" or (not thinking and card is None):
            chunks.append(msg)
    return "".join(chunks)

def clean_markdown(text: str) -> str:
    """Strip Grok XML citation/render tags and tidy whitespace."""
    text = re.sub(r'<grok:render\b[^>]*>.*?</grok:render>', '', text, flags=re.DOTALL)
    text = re.sub(r'</?(?:grok|xai):[^>]*>', '', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'[ \t]+$', '', text, flags=re.MULTILINE)
    return text.strip()

def to_plain(text: str) -> str:
    """Strip Markdown formatting for short/plain output."""
    text = clean_markdown(text)
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)   # bold
    text = re.sub(r'\*(.+?)\*',     r'\1', text)   # italic
    text = re.sub(r'#{1,6}\s+',     '',    text)   # headers
    text = re.sub(r'^\s*[-*]\s+',   '',    text, flags=re.MULTILINE)  # bullets
    text = re.sub(r'\n{2,}',        ' ',   text)   # collapse paragraphs
    text = re.sub(r'\s+',           ' ',   text)
    # strip "Short answer:" / "Short answer only." prefix Grok sometimes echoes
    text = re.sub(r'^short answer\s*(?:only[.]?)?\s*', '', text, flags=re.IGNORECASE)
    return text.strip()

def main():
    cfg = load_config()

    ap = argparse.ArgumentParser(
        description="Grok AI CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("query",      nargs="*",        help="Query text")
    ap.add_argument("--conv",     default=cfg.get("default_conv", "main"), metavar="NAME",
                    help="Conversation slot name (default: main, or default_conv in config)")
    ap.add_argument("--new",      action="store_true",
                    help="Start a new conversation on this slot")
    ap.add_argument("--list",     action="store_true",
                    help="List all conversation slots")
    ap.add_argument("--history",  nargs="?", const=True, default=False, metavar="NAME",
                    help="Show query history per slot (clipped), including "
                         "archived conversation ids. Optionally pass a slot name.")
    ap.add_argument("--use-id",   default=None, metavar="CONV_ID",
                    help="Reactivate a past conversation id (active or archived, "
                         "from any slot) as the current conversation on --conv. "
                         "The slot's previously-active conversation is archived, never lost.")
    ap.add_argument("--short",    action="store_true", default=cfg_bool(cfg, "short", False),
                    help="Request short answer; output as plain text")
    ap.add_argument("--md",       action="store_true", default=cfg_bool(cfg, "force_md", False),
                    help="Force Markdown output even with --short")
    ap.add_argument("--save",     action="store_true",
                    default=cfg_bool(cfg, "auto_save", False),
                    help=f"Save raw NDJSON .json to {LOGS_DIR}")
    ap.add_argument("-q", "--quiet", action="store_true",
                    default=cfg_bool(cfg, "quiet", False),
                    help="Suppress '[saved: ...]' and other stderr status messages")
    ap.add_argument("--model",    default=cfg.get("model", "grok-3"), metavar="MODEL",
                    help="Model to use (default: grok-3, or model in config)")
    ap.add_argument("--search",   action="store_true", default=cfg_bool(cfg, "search", False),
                    help="Enable web search results")
    ap.add_argument("--citations",action="store_true", default=cfg_bool(cfg, "citations", False),
                    help="Enable citations")
    ap.add_argument("--rentry",   action="store_true",
                    default=cfg_bool(cfg, "auto_rentry", False),
                    help="Upload response Markdown to rentry.co as a fresh paste "
                         "(random url, not stored or reused); url and edit code are printed")
    args = ap.parse_args()

    if args.list:
        list_convs()
        return

    if args.history:
        name = args.history if isinstance(args.history, str) else None
        show_history(name)
        return

    if args.use_id:
        use_conv_id(args.conv, args.use_id)
        return

    auth_token  = cfg.get("auth_token", "")
    csrf_token  = cfg.get("x_csrf_token", "")
    if not auth_token or not csrf_token:
        print(
            "Error: auth_token and x_csrf_token required.\n"
            f"Set them in {CONFIG_FILE}:\n"
            "  auth_token=YOUR_TOKEN\n"
            "  x_csrf_token=YOUR_CSRF_TOKEN\n"
            "Or export AUTH_TOKEN / X_CSRF_TOKEN as environment variables.",
            file=sys.stderr,
        )
        sys.exit(1)

    headers = make_headers(auth_token, csrf_token)

    # --new with no query just resets
    if args.new and not args.query:
        conv_id = new_conversation(headers, args.conv)
        print(f"New conversation started: {args.conv} / {conv_id}")
        return

    if not args.query:
        ap.print_help()
        sys.exit(0)

    query_text = " ".join(args.query)
    if args.short:
        query_text = f"short answer only. {query_text}"

    conv_id = get_or_create_conv(headers, args.conv, args.new)

    payload = {
        "responses": [{
            "message":        query_text,
            "sender":         1,
            "promptSource":   "",
            "fileAttachments": [],
        }],
        "systemPromptName":  "",
        "grokModelOptionId": args.model,
        "conversationId":    conv_id,
        "returnSearchResults": args.search,
        "returnCitations":     args.citations,
        "promptMetadata": {
            "promptSource": "NATURAL",
            "action":       "INPUT",
        },
        "imageGenerationCount": 4,
        "requestFeatures": {
            "eagerTweets":   False,
            "serverHistory": False,
        },
    }

    try:
        raw_bytes = http_post(ADD_RESPONSE_URL, headers, payload)
    except urllib.error.HTTPError as e:
        print(f"HTTP error {e.code}: {e.reason}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Request failed: {e}", file=sys.stderr)
        sys.exit(1)

    ndjson_text = raw_bytes.decode("utf-8", errors="replace")

    if args.save:
        LOGS_DIR.mkdir(parents=True, exist_ok=True)
        out_file = LOGS_DIR / f"{int(time.time())}.json"
        out_file.write_text(ndjson_text)
        if not args.quiet:
            print(f"[saved: {out_file}]", file=sys.stderr)

    message = extract_message(ndjson_text)
    if not message:
        print("(no response)", file=sys.stderr)
        sys.exit(1)

    if args.short and not args.md:
        plain = to_plain(message)
        print(plain)
        append_turn(args.conv, query_text, plain)
        if args.rentry:
            try:
                rentry_publish(plain)
            except Exception as e:
                print(f"[rentry upload failed: {e}]", file=sys.stderr)
    else:
        md = clean_markdown(message)
        print(md)
        append_turn(args.conv, query_text, md)
        if args.rentry:
            try:
                rentry_publish(md)
            except Exception as e:
                print(f"[rentry upload failed: {e}]", file=sys.stderr)

if __name__ == "__main__":
    main()
