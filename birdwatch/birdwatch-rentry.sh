#!/bin/bash
# Fetch Birdwatch (Community Notes) from tweet by id
# rewrites x icon with a bird
# requires: https://github.com/radude/rentry
#           https://github.com/simonw/shot-scraper
# direct tweet url or id as input
# ex ./birwatch-rentry.sh https://x.com/elonmusk/status/1838337595970847103

#x_csrf_token="" #ct0
#auth_token=""

. ~/.env-twitter

####

usage() { echo "$0 tweet_id or url"; exit 1; }
[ "$#" -ne 1 ] && usage
tweet_id="$1"
d=$(date +%s)

bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'
header=(
  -H "Authorization: Bearer ${bearer_token}"
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
  -H "X-Csrf-Token: ${x_csrf_token}"
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}"
)

variables='{"tweet_id":"'"${tweet_id##*/}"'"}'
api='https://x.com/i/api/graphql/3G9Ms1POEEiF86dFhV-tTg/BirdwatchFetchNotes'
features='{"responsive_web_birdwatch_media_notes_enabled":true,"responsive_web_birdwatch_url_notes_enabled":true,"responsive_web_birdwatch_translation_enabled":true,"responsive_web_birdwatch_fast_notes_badge_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":true}'

twimg=$(
  shot-scraper "http://x.com/_/status/${tweet_id##*/}" \
  -a ~/.auth-ss-twitter.json \
  -h 1080 \
  -b firefox \
  -o /tmp/tweet.png \
  -p -3 \
  --wait 3000 \
  -s 'section.css-175oi2r:nth-child(3) > div:nth-child(2) > div:nth-child(1) > div:nth-child(1) > div:nth-child(1)' \
  -j 'document.querySelector(".r-1mmae3n.r-1h8ys4a.css-175oi2r > div.css-175oi2r:nth-of-type(1) > .css-175oi2r > .r-3pj75a.css-175oi2r").remove();document.querySelector(".r-18u37iz.r-1h0z5md").remove();document.querySelector(".r-sdzlij.r-1phboty.r-rs99b7.r-lrvibr.r-15ysp7h.r-4wgw6l.r-3pj75a.r-1loqt21.r-o7ynqc.r-6416eg.r-1ny4l3l").remove();document.querySelector(".r-1hdv0qi > g > path").setAttribute("d", "M23.643 4.937c-.835.37-1.732.62-2.675.733.962-.576 1.7-1.49 2.048-2.578-.9.534-1.897.922-2.958 1.13-.85-.904-2.06-1.47-3.4-1.47-2.572 0-4.658 2.086-4.658 4.66 0 .364.042.718.12 1.06-3.873-.195-7.304-2.05-9.602-4.868-.4.69-.63 1.49-.63 2.342 0 1.616.8233.043 2.072 3.878-.764-.025-1.482-.234-2.11-.583v.06c0 2.257 1.605 4.14 3.737 4.568-.392.106-.803.162-1.227.162-.3 0-.593-.028-.877-.082.593 1.85 2.313 3.198 4.352 3.234-1.595 1.25-3.604 1.995-5.786 1.995-.376 0-.747-.022-1.112-.065 2.062 1.323 4.51 2.093 7.14 2.093 8.57 0 13.255-7.098 13.255-13.254 0-.2-.005-.402-.014-.602.91-.658 1.7-1.477 2.323-2.41z");document.querySelector(".r-xoduu5").style.cssText="fill:#1DA1F2;"' > /dev/null 2>&1 
)

imgur_url=$(img /tmp/tweet.png)

birdwatch=$(
  curl -s -G "${header[@]}" "${api}" \
    --data-urlencode "variables=${variables}" \
    --data-urlencode "features=${features}" |
    jq -r '.data.tweet_result_by_rest_id | if .result then .result else empty end | if .tweet then .tweet else . end | "##### MISLEADING\n\(.misleading_birdwatch_notes.notes[] | "\(if(.rating_status == "CurrentlyRatedHelpful") then "##### Visible on Twitter http://x.com/_/status/\(.tweet_results.result.rest_id)" else "" end)\n[[view note]](https://x.com/i/birdwatch/n/\(.rest_id)) - \(.birdwatch_profile.alias) (Shown notes: \(.birdwatch_profile.notes_count.currently_rated_helpful) · Rating impact: \(.birdwatch_profile.ratings_count.successful.total))\n\(.data_v1.summary.text)")\n","##### NOT MISLEADING\n\(.not_misleading_birdwatch_notes.notes[] | "\(if(.rating_status == "CurrentlyRatedHelpful") then "##### Visible on Twitter http://x.com/_/status/\(.tweet_results.result.rest_id)" else "" end)\n[[view note]](https://x.com/i/birdwatch/n/\(.rest_id)) - \(.birdwatch_profile.alias) (Shown notes: \(.birdwatch_profile.notes_count.currently_rated_helpful) · Rating impact: \(.birdwatch_profile.ratings_count.successful.total))\n\(.data_v1.summary.text)")\n"'
)

echo -e "![](${imgur_url})\n\nhttps://nitter.net/_/status/${tweet_id##*/}\n${birdwatch}" |
  rentry new # | tee -a ~/rentry_urls
