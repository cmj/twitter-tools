#!/usr/bin/env bash
# No auth Twitter endpoints test 
# ./endpoints.sh <auth_token>

# UserByScreenName
# TweetResultByRestId
# UserTweets - sorted by most liked: profile_best_highlights 

auth_token=$1
x_csrf_token=$(openssl rand -hex 16)
query="fish"
product="Latest" # Latest | Top
count=20 # 1-20
user_id=12 # @jack
user_id2=783214 # X
tweet_id=20 # @jack - just setting up my twttr
screen_name="jack"
list_id=1860883 # @mashable - Social Media
list_slug="social-media"

# main.js
#bearer_token='AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'

# Twitter for Android - all work
bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'

# Twitter for iPhone - all work
#bearer_token="AAAAAAAAAAAAAAAAAAAAAAj4AQAAAAAAPraK64zCZ9CSzdLesbE7LB%2Bw4uE%3DVJQREvQNCZJNiz3rHO7lOXlkVOQkzzdsgu6wWgcazdMUaGoUGm"

# Twitter for Mac - 3 only - UserWithProfileTweetsAndRepliesQueryV2 ListByRestId Retweeters
bearer_token="AAAAAAAAAAAAAAAAAAAAAIWCCAAAAAAA2C25AxqI%2BYCS7pdfJKRH8Xh19zA%3D8vpDZzPHaEJhd20MKVWp3UR38YoPpuTX7UD2cVYo3YNikubuxd"

####
#if [[ -z "$auth_token" ]]; then echo "Usage: $0 auth_token"; exit 1; fi

domain='https://x.com'
path='/i/api/graphql/'
url="${domain}${path}"
endpoints=(
  '-oaLodhGbbnzJBACb1kk2Q/UserByScreenName'
  'u7wQyGi6oExe8_TRWGMq4Q/UserResultByScreenNameQuery'
  'oPppcargziU1uDQHAUmH-A/UserResultByIdQuery'
  'xavgLWWbFH8wm_8MQN8plQ/UsersByRestIds'
  'ujL_oXbgVlDHQzWSTgzvnA/UsersByScreenNames'
  '3JNH4e9dq1BifLxAa3UMWg/UserWithProfileTweetsQueryV2'
  '8IS8MaO-2EN6GZZZb8jF0g/UserWithProfileTweetsAndRepliesQueryV2'
  '36oKqyQ7E_9CmtONGjJRsA/UserMedia'
  'PDfFf8hGeJvUCiTyWtw4wQ/MediaTimelineV2'
  'q94uRCEn65LZThakYcPT6g/TweetDetail'
  '7xflPyRiUxGVbJd4uWmbfg/TweetResultByRestId'
  'nzme9KiYhfIOrrLrPP_XeQ/TweetResultByIdQuery'
  'gkjsKepM6gl_HmFWoWKfgg/SearchTimeline'
  'iTpgCtbdxrsJfyx0cFjHqg/ListByRestId'
  '-kmqNvm5Y-cVrfvBy6docg/ListBySlug'
  'P4NpVZDqUD_7MEM84L-8nw/ListMembers'
  'BbGLL1ZfMibdFNWlk7a0Pw/ListTimeline'
  'oRJs8SLCRNRbQzuZG93_oA/UserTweets'
  'kkaJ0Mf34PZVarrxzLihjg/UserTweetsAndReplies'
  'Y4Erk_-0hObvLpz0Iw3bzA/ConversationTimeline'
  'k3rtLsS9kG5hI-Jr0dTMCg/ConversationTimelineV2'
  'wfglZEC0MRgBdxMa_1a5YQ/Retweeters'
  'WJbdU-1ay4MHL8nKqCZYUQ/Following'
  'kuFUYP9eV1FPoEy4N-pi7w/Followers'
  'F0OBVdpsc0USbDeD456R5w/fetchUsersQuery'
  'qZ92r6KDO0_GZxVJGM33XA/AboutAccountQuery'
)

request_endpoint() {
  # uncomment to save output
  json_file="/tmp/${opt##*/}-$EPOCHSECONDS.json"
  
  guest_token=$(curl -s -XPOST -H "Authorization: Bearer ${bearer_token}" "https://api.twitter.com/1.1/guest/activate.json" | jq -r '.guest_token')
  URL="${url}${opt}"
  VARIABLES='{"screen_name":"'"${screen_name}"'","screenName":"'"${screen_name}"'","screen_names":["x","jack"],"rawQuery":"'"${query}"'","query":"'"${query}"'","userId":"'"${user_id}"'","userIds":["'"${user_id}"'","'"${user_id2}"'"],"rest_id":"'"${user_id}"'","postId":"'"${tweet_id}"'","focalTweetId":"'"${tweet_id}"'","tweetId":"'"${tweet_id}"'","query_source":"typed_query","count":'"${count}"',"querySource":"typed_query","product":"'"${product}"'","listId":"'"${list_id}"'","includePromotedContent":false,"withBirdwatchNotes":true,"withVoice":true,"withCommunity":false,"listSlug":"'"${list_slug}"'","withDownvotePerspective":true,"withReactionsMetadata":true,"withReactionsPerspective":true}'
  FEATURES='{"android_graphql_skip_api_media_color_palette":false,"blue_business_profile_image_shape_enabled":false,"creator_subscriptions_subscription_count_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"freedom_of_speech_not_reach_fetch_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"hidden_profile_likes_enabled":false,"highlights_tweets_tab_ui_enabled":false,"interactive_text_enabled":false,"longform_notetweets_consumption_enabled":true,"longform_notetweets_inline_media_enabled":false,"longform_notetweets_richtext_consumption_enabled":true,"longform_notetweets_rich_text_read_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"responsive_web_enhance_cards_enabled":false,"responsive_web_graphql_exclude_directive_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_media_download_video_enabled":false,"responsive_web_text_conversations_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"responsive_web_twitter_blue_verified_badge_is_enabled":true,"rweb_lists_timeline_redesign_enabled":true,"spaces_2022_h2_clipping":true,"spaces_2022_h2_spaces_communities":true,"standardized_nudges_misinfo":false,"subscriptions_verification_info_enabled":true,"subscriptions_verification_info_reason_enabled":true,"subscriptions_verification_info_verified_since_enabled":true,"super_follow_badge_privacy_enabled":false,"super_follow_exclusive_tweet_notifications_enabled":false,"super_follow_tweet_api_enabled":false,"super_follow_user_api_enabled":false,"tweet_awards_web_tipping_enabled":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"tweetypie_unmention_optimization_enabled":false,"unified_cards_ad_metadata_container_dynamic_card_content_query_enabled":false,"verified_phone_label_enabled":false,"vibe_api_enabled":false,"view_counts_everywhere_api_enabled":false,"c9s_tweet_anatomy_moderator_badge_enabled":false,"rweb_video_timestamps_enabled":false,"rweb_tipjar_consumption_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"articles_preview_enabled":false,"tweet_with_visibility_results_prefer_gql_media_interstitial_enabled":false,"communities_web_enable_tweet_community_results_fetch":false,"responsive_web_grok_analyze_post_followups_enabled":false,"responsive_web_grok_image_annotation_enabled":false,"premium_content_api_read_enabled":false,"responsive_web_grok_community_note_auto_translation_is_enabled":false,"rweb_video_screen_enabled":false,"responsive_web_profile_redirect_enabled":false,"responsive_web_grok_show_grok_translated_post":false,"responsive_web_grok_imagine_annotation_enabled":false,"responsive_web_grok_analyze_button_fetch_trends_enabled":false,"responsive_web_grok_share_attachment_enabled":false,"profile_label_improvements_pcf_label_in_post_enabled":false,"responsive_web_jetfuel_frame":false,"responsive_web_grok_analysis_button_from_backend":false,"hidden_profile_subscriptions_enabled":false,"responsive_web_twitter_article_notes_tab_enabled":false,"subscriptions_feature_can_gift_premium":false,"subscriptions_verification_info_is_identity_verified_enabled":false,"payments_enabled":false}'
  
  output=$(curl -siG "${URL}" \
    -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:148.0) Gecko/20100101 Firefox/148.0' \
    -H "authorization: Bearer ${bearer_token}"  \
    -H "x-guest-token: ${guest_token}" \
    --data-urlencode "variables=${VARIABLES}" \
    --data-urlencode "features=${FEATURES}" 2>&1 |
    egrep  '^x-rate|^HTTP|^\{"')

  if [[ "$json_file" ]]; then
      grep '^\{"' <<< "${output}" | tee "${json_file}" | jq -c
    else
      grep '^\{"' <<< "${output}" | jq -c
  fi
  
  echo '-----'
  echo $URL
  sed -En -e 's/^([xH].*)\r/\1/p' <<< "${output}" |
    sort |
    cut -d\  -f2 |
    xargs |
    while read status limit remaining reset; do 
      echo -e "status: $status limit: \x1b[32m$remaining/$limit\x1b[0m reset: \x1b[94m$(date -d@$reset '+%a %T')\x1b[0m"
    done
}

PS3="Choose endpoint ('enter' for list, ^C to quit): "
select opt in "${endpoints[@]}"; do
  request_endpoint
done
