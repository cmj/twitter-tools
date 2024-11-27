#!/bin/bash
# Fetch Birdwatch (Community Notes) data
# Requires Twitter account, 2 parameters from header
# direct link url format: https://x.com/i/birdwatch/n/:id
# ex: https://x.com/i/birdwatch/n/1838402358264361370

x_csrf_token=''
auth_token=''

####

usage() { echo "$0 note_id"; exit 1; }
[ "$#" -ne 1 ] && usage
note_id="$1"

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: TwitterAndroid/10.21.1" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

api='https://x.com/i/api/graphql/TCCuBAotz4ejz0_9iGjm6w/BirdwatchFetchOneNote'

variables='{"note_id":"'"${note_id}"'"}'
features='{"responsive_web_birdwatch_media_notes_enabled":true,"responsive_web_birdwatch_url_notes_enabled":true,"responsive_web_birdwatch_translation_enabled":true,"responsive_web_birdwatch_fast_notes_badge_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":true}'

curl -s -G "${header[@]}" "${api}" \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq
