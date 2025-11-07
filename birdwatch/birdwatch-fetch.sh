#!/bin/bash
# Fetch Birdwatch Notes (Community Notes) from tweet by id
# Requires Twitter account, 2 parameters from header
# direct tweet url or id as input
# ex ./birwatch-fetch.sh https://x.com/elonmusk/status/1838337595970847103

if [ -f .env ]; then
  . .env
    if [[ -z $auth_token || -z $x_csrf_token ]]; then
      echo "set auth_token and x_csrf_token in .env"; exit 1
    fi
  else
    echo "set credentials in .env"; exit 1
fi

####

usage() { echo "$0 tweet_id or url"; exit 1; }
[ "$#" -ne 1 ] && usage

tweet_id="$1"

api='https://x.com/i/api/graphql/3G9Ms1POEEiF86dFhV-tTg/BirdwatchFetchNotes'
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

variables='{"tweet_id":"'"${tweet_id##*/}"'"}'
features='{"responsive_web_birdwatch_media_notes_enabled":true,"responsive_web_birdwatch_url_notes_enabled":false,"responsive_web_birdwatch_translation_enabled":true,"responsive_web_birdwatch_fast_notes_badge_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false}'

curl -s -G "${header[@]}" $api \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq -r '.data.tweet_result_by_rest_id.result | "## NOT MISLEADING\n\(.not_misleading_birdwatch_notes.notes[].data_v1.summary.text)\n","## MISLEADING\n\(.misleading_birdwatch_notes.notes[].data_v1.summary.text)\n"'
