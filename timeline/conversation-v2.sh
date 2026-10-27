#!/bin/bash
# v2 conversation example

# source env file for auth_token, x_csrf_token (ct0)
. $HOME/.env-twitter

tweet_id="${1:-2113776971603689874}"

bearer_token="AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

header=(
  -H "Authorization: Bearer ${bearer_token}"
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
  -H "X-Csrf-Token: ${x_csrf_token}"
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}"
)

params="count=1&include_reply_count=true&cards_platform=Web-13&include_entities=1&include_user_entities=1&include_cards=1&send_error_codes=1&tweet_mode=extended&include_ext_alt_text=true"

curl -s "${header[@]}" \
  "https://x.com/i/api/2/timeline/conversation/${tweet_id}.json?${params}" |
  jq
