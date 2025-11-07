#!/bin/bash
# Fetch retweeters from tweetId

id=$1

if [ -f .env ]; then
  . ~/.env-twitter
    if [[ -z $auth_token || -z $x_csrf_token ]]; then
      echo "set auth_token and x_csrf_token in .env"; exit 1
    fi
  else
    echo "set credentials in .env"; exit 1
fi

####

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")


url='https://api.twitter.com/graphql/RCR9gqwYD1NEgi9FWzA50A/Retweeters'
variables='{"tweetId":"'"${id}"'","count":200,"includePromotedContent":false}'
features='{"android_graphql_skip_api_media_color_palette":false,"blue_business_profile_image_shape_enabled":false,"c9s_tweet_anatomy_moderator_badge_enabled":false,"creator_subscriptions_subscription_count_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"freedom_of_speech_not_reach_fetch_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"hidden_profile_likes_enabled":false,"highlights_tweets_tab_ui_enabled":false,"interactive_text_enabled":false,"longform_notetweets_consumption_enabled":true,"longform_notetweets_inline_media_enabled":false,"longform_notetweets_richtext_consumption_enabled":true,"longform_notetweets_rich_text_read_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"responsive_web_enhance_cards_enabled":false,"responsive_web_graphql_exclude_directive_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_media_download_video_enabled":false,"responsive_web_text_conversations_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"responsive_web_twitter_blue_verified_badge_is_enabled":true,"rweb_lists_timeline_redesign_enabled":true,"rweb_video_timestamps_enabled":true,"spaces_2022_h2_clipping":true,"spaces_2022_h2_spaces_communities":true,"standardized_nudges_misinfo":false,"subscriptions_verification_info_enabled":true,"subscriptions_verification_info_reason_enabled":true,"subscriptions_verification_info_verified_since_enabled":true,"super_follow_badge_privacy_enabled":false,"super_follow_exclusive_tweet_notifications_enabled":false,"super_follow_tweet_api_enabled":false,"super_follow_user_api_enabled":false,"tweet_awards_web_tipping_enabled":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"tweetypie_unmention_optimization_enabled":false,"unified_cards_ad_metadata_container_dynamic_card_content_query_enabled":false,"verified_phone_label_enabled":false,"vibe_api_enabled":false,"view_counts_everywhere_api_enabled":false}'

####
curl -s -G "${header[@]}" $url \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq 

