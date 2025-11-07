#!/bin/bash
# Twitter user via UserByRestId

# set auth_token and x_csrf_token in .env
source .env

id=$1

usage() { echo "$0 userId"; exit 1; }
[ ! "$*" ] && usage

####
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")
api='https://x.com/i/api/graphql/cyctxGFWi-3N5RUlEWQhWg/UserByRestId'
variables='{"userId":'"${id}"',"includePromotedContent":false,"withBirdwatchNotes":true,"withVoice":true}'
features='{"hidden_profile_subscriptions_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"highlights_tweets_tab_ui_enabled":true,"responsive_web_twitter_article_notes_tab_enabled":true,"subscriptions_feature_can_gift_premium":false,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true}'

#### pretty print
curl -s -G "${header[@]}" $api \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq -r '.data.user.result.legacy.screen_name'

# or pretty print
#jq '.data.user.result.legacy | "\(.screen_name) (\(.name)) | \(.description) | tweets: \(.statuses_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")) | friends: \(.friends_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")) | followers: \(.followers_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")) | likes: \(.favourites_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")) | loc: \(.location) | id: \(.id_str) | \(.created_at) | \(if(.entities.url.urls[0]) then .entities.url.urls[0].expanded_url else "" end) https://x.com/\(.screen_name)"' | sed 's/\\n/ /g;s/^\"//;s/\"$//'
