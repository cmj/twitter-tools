#!/usr/bin/env python3

import os
import sys
import time
import json
import subprocess
import requests
from pathlib import Path

API = "https://x.com/i/api/graphql/3G9Ms1POEEiF86dFhV-tTg/BirdwatchFetchNotes"

BEARER_TOKEN = (
    "AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
)

FEATURES = {
    "responsive_web_birdwatch_media_notes_enabled": True,
    "responsive_web_birdwatch_url_notes_enabled": True,
    "responsive_web_birdwatch_translation_enabled": True,
    "responsive_web_birdwatch_fast_notes_badge_enabled": True,
    "responsive_web_graphql_timeline_navigation_enabled": True,
    "rweb_tipjar_consumption_enabled": True,
    "responsive_web_graphql_exclude_directive_enabled": True,
    "verified_phone_label_enabled": True,
    "responsive_web_graphql_skip_user_profile_image_extensions_enabled": True,
}


def load_env():
    env_path = Path.home() / ".env-twitter"
    if not env_path.exists():
        print("~/.env-twitter not found")
        sys.exit(1)

    env = {}
    for line in env_path.read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"')
    return env


def get_tweet_id(arg):
    return arg.split("/")[-1]


def run_shot_scraper(tweet_id):
    cmd = [
        "shot-scraper",
        f"http://x.com/_/status/{tweet_id}",
        "-a", str(Path.home() / ".auth-ss-twitter.json"),
        "-h", "1080",
        "-b", "firefox",
        "-o", "/tmp/tweet.png",
        "-p", "-3",
        "--wait", "3000",
        "-s",
        "section.css-175oi2r:nth-child(3) > div:nth-child(2) > div:nth-child(1) > div:nth-child(1) > div:nth-child(1)",
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def upload_img():
    result = subprocess.run(
        ["img", "/tmp/tweet.png"],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def fetch_birdwatch(tweet_id, csrf, auth):
    headers = {
        "Authorization": f"Bearer {BEARER_TOKEN}",
        "User-Agent": "Mozilla/5.0",
        "X-Csrf-Token": csrf,
        "Cookie": f"ct0={csrf}; auth_token={auth}",
    }

    params = {
        "variables": json.dumps({"tweet_id": tweet_id}),
        "features": json.dumps(FEATURES),
    }

    r = requests.get(API, headers=headers, params=params)
    r.raise_for_status()
    return r.json()


def format_notes(data):
    result = data.get("data", {}).get("tweet_result_by_rest_id", {})
    result = result.get("result") or result
    tweet = result.get("tweet") if isinstance(result, dict) else result
    root = tweet or result

    output = []

    def process_section(title, section_key):
        notes = root.get(section_key, {}).get("notes", [])
        if not notes:
            return

        output.append(f"##### {title}")

        for note in notes:
            visible = ""
            if note.get("rating_status") == "CurrentlyRatedHelpful":
                rest_id = note.get("tweet_results", {}).get("result", {}).get("rest_id")
                visible = f"##### Visible on Twitter http://x.com/_/status/{rest_id}\n"

            alias = note["birdwatch_profile"]["alias"]
            helpful = note["birdwatch_profile"]["notes_count"]["currently_rated_helpful"]
            impact = note["birdwatch_profile"]["ratings_count"]["successful"]["total"]
            summary = note["data_v1"]["summary"]["text"]

            output.append(
                f"""{visible}[[view note]](https://x.com/i/birdwatch/n/{note['rest_id']}) - {alias} (Shown notes: {helpful} · Rating impact: {impact})

{summary}
"""
            )

    process_section("MISLEADING", "misleading_birdwatch_notes")
    process_section("NOT MISLEADING", "not_misleading_birdwatch_notes")

    return "\n".join(output)


def create_rentry(markdown):
    proc = subprocess.Popen(
        ["rentry", "new"],
        stdin=subprocess.PIPE,
        text=True,
    )
    proc.communicate(markdown)


def main():
    if len(sys.argv) != 2:
        print("usage: birdwatch_rentry.py tweet_id_or_url")
        sys.exit(1)

    tweet_id = get_tweet_id(sys.argv[1])

    env = load_env()
    csrf = env.get("x_csrf_token")
    auth = env.get("auth_token")

    run_shot_scraper(tweet_id)
    imgur_url = upload_img()

    data = fetch_birdwatch(tweet_id, csrf, auth)
    notes_md = format_notes(data)

    final_md = f"""![]({imgur_url})

https://nitter.net/_/status/{tweet_id}

{notes_md}
"""

    create_rentry(final_md)


if __name__ == "__main__":
    main()

