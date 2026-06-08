#!/usr/bin/env bash
# Print the latest "For You" trending news stories from Twittter/X
# requires: twitter auth/csrf tokens, jq
# optional: mdcat, ct (chromaterm for custom colorized output) 

# story number, [category] (news, entertainment, etc), title
# story hook
# date created (localtime) | tweet count | trending url

# ┄┄┄23 [News] - Senate Rejects SAVE America Act in 48-50 Vote Amid Border Funding Debate
# Four Republican senators crossed party lines to join Democrats, blocking a key House-passed bill aimed at tightening federal voter rules.
# 2026-06-05 05:25:44 | tweets: 15062 | https://x.com/i/trending/2062873504043950224

limit=25      # 1-25
reverse=false # true for newest first
sort_by=".core.created_at_ms"  # .core.created_at_ms | .core.category | .post_count
title_only=false

###

if [[ -z $auth_token || -z $x_csrf_token ]]; then
  . $HOME/.env-twitter 2>/dev/null || { echo "set credentials in ~/.env-twitter"; exit 1; }
  [[ -n $auth_token && -n $x_csrf_token ]] || { echo "set auth_token and x_csrf_token in ~/.env-twitter"; exit 1; }
fi

usage() {
  echo "Usage: $(basename "$0") [-l limit] [-r] [-s sort_field]"
  echo "  -l  Result limit (1-25, default: ${limit})"
  echo "  -r  Reverse order (newest/highest first)"
  echo "  -s  Sort field: created_at_ms | category | post_count (default: created_at_ms)"
  echo "  -t  Display title, story headlines only"
  exit 1
}

while getopts "l:rs:th" opt; do
  case $opt in
    l) limit="$OPTARG" ;;
    r) reverse=true ;;
    s) case "$OPTARG" in
         created_at_ms|category|post_count) sort_by="$OPTARG" ;;
         *) echo "Invalid sort field: $OPTARG"; usage ;;
       esac ;;
    t) title_only=true ;;
    h) usage ;;
    *) usage ;;
  esac
done

bearer_token='AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
url="https://x.com/i/api/graphql/I3V_Tt32aTZdw7cBdKUJbg/useStoryTopicQuery"
variables='{"rest_id":"For You","limit":'"${limit}"'}'
headers=(
  -H "Authorization: Bearer ${bearer_token}"
  -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:146.0) Gecko/20100101 Firefox/146.0'
  -H "X-Csrf-Token: ${x_csrf_token}"
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}"
)

request=$(curl -sG "${headers[@]}" "${url}" --data-urlencode "variables=${variables}")

# pretty output
jq -r --argjson rev "${reverse}" --arg sort_by "${sort_by}" --argjson title_only "${title_only}" '
  [.data.story_topic.stories.items[].trend_results.result]
  | sort_by(
      if $sort_by == "post_count" then (.post_count | tonumber)
      elif $sort_by == "category"  then .core.category
      else .core.created_at_ms
      end
    )
  | if $rev then reverse else . end
  | to_entries[]
  | "### \(.key + 1) [\(.value.core.category)] - \(.value.core.name)",
    (if $title_only | not then
      (if .value.core.hook then "\(.value.core.hook)" else empty end),
      "\n\(.value.core.created_at_ms | (. / 1000 | floor) | strflocaltime("%Y-%m-%d %H:%M:%S")) | tweets: \(.value.post_count) | https://x.com/i/trending/\(.value.rest_id)\n"
    else empty end)
' <<< "${request}" #| mdcat | ct


