#!/bin/bash
# Fetch TVHomeMixer - Twitter TV app feed
# Requires Twitter account, 2 parameters from header

if [ -f .env ]; then
  . .env
    if [[ -z $auth_token || -z $x_csrf_token ]]; then
      echo "set auth_token and x_csrf_token in .env"; exit 1
    fi
  else
    echo "set credentials in .env"; exit 1
fi

screen_name=$1
if [ -z $screen_name ]; then echo "Usage: $0 screen_name"; exit 1; fi

####

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Twitterbot" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")
variables='{"userId":1559556660640849921,"includePromotedContent":false,"withBirdwatchNotes":true,"withVoice":true}'

user-id() {
  api=https://x.com/i/api/graphql/laYnJPCAcVo0o6pzcnlVxQ/UserByScreenName
  variables='{"screen_name":"'"$screen_name"'","includePromotedContent":false,"withBirdwatchNotes":true,"withVoice":true}'
  features='{"hidden_profile_subscriptions_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"subscriptions_verification_info_is_identity_verified_enabled":true,"subscriptions_verification_info_verified_since_enabled":true,"highlights_tweets_tab_ui_enabled":true,"responsive_web_twitter_article_notes_tab_enabled":true,"subscriptions_feature_can_gift_premium":false,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true}'
  curl -s -G "${header[@]}" $api \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq -r .data.user.result.rest_id
}

api=https://x.com/i/api/graphql/Yh74Ee_JLrurM9BqRmegyw/UserCreatorSubscribers
variables='{"userId":"'"$(user-id)"'","limit":100,"includePromotedContent":false,"withBirdwatchNotes":true,"withVoice":true}'
features='{"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"rweb_video_timestamps_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"responsive_web_enhance_cards_enabled":false}'

####
curl -s -G "${header[@]}" $api \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq -r 'if(.data.user.result.timeline.timeline.instructions[-1]) then .data.user.result.timeline.timeline.instructions[-1].entries[].content.itemContent.user_results.result.legacy.screen_name | select( . != null ) else "No subscribers" end'

