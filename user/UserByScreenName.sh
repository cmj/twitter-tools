#!/bin/bash
# Retrieve info for an account by Twitter handle.

screen_name=$1

. .env 

if [ -z $screen_name ]; then echo "Usage: $0 screen_name"; exit 1; fi

####
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: TwitterAndroid/10.21.1" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")
variables='{"screen_name":"'"$screen_name"'","includePromotedContent":false,"withBirdwatchNotes":true,"withVoice":true}'
api=https://x.com/i/api/graphql/laYnJPCAcVo0o6pzcnlVxQ/UserByScreenName
features='{"hidden_profile_subscriptions_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"subscriptions_verification_info_is_identity_verified_enabled":true,"subscriptions_verification_info_verified_since_enabled":true,"highlights_tweets_tab_ui_enabled":true,"responsive_web_twitter_article_notes_tab_enabled":true,"subscriptions_feature_can_gift_premium":false,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true}'
####
curl -s -G "${header[@]}" $api \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq 

