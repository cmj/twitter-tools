#!/usr/bin/env bash
# Request timeline as guest 

#screen_name="NWS_NTWC"
screen_name="${1/@}"

[ -z "$screen_name" ] && echo "Usage: $0 <screen_name>" && exit 1

user_agent="TwitterAndroid/10.21.1"
bearer_token='AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
json_file="/tmp/${endpoint##*/}-$EPOCHSECONDS.json"
guest_token=$(curl -s -XPOST -H "Authorization: Bearer ${bearer_token}" "https://api.twitter.com/1.1/guest/activate.json" | jq -r '.guest_token')

HEADERS=(
  -H "Authorization: Bearer ${bearer_token}"
  -H "User-Agent: ${user_agent}"
  -H "x-guest-token: ${guest_token}"
)

USER_URL='https://x.com/i/api/graphql/-oaLodhGbbnzJBACb1kk2Q/UserByScreenName'
USER_VARIABLES='{"screen_name":"'"${screen_name}"'"}'
USER_FEATURES='{"hidden_profile_likes_enabled":false,"hidden_profile_subscriptions_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"subscriptions_verification_info_is_identity_verified_enabled":false,"subscriptions_verification_info_verified_since_enabled":true,"highlights_tweets_tab_ui_enabled":true,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true}'

user_lookup=$(curl -sG "${USER_URL}" "${HEADERS[@]}" --data-urlencode "variables=${USER_VARIABLES}" --data-urlencode "features=${USER_FEATURES}")
user_id=$(jq -r .data.user.result.rest_id <<< "${user_lookup}")

if [[ "$user_id" == null ]]; then echo "Invalid username"; exit 1; fi

# grab proper upper/lower case
screen_name=$(jq -r '.data.user.result.core.screen_name' <<< "${user_lookup}")

#echo "USER_ID: $user_id"

TWEETS_URL='https://api.x.com/graphql/oRJs8SLCRNRbQzuZG93_oA/UserTweets'
TWEETS_VARIABLES='{"userId":"'"${user_id}"'","count":20,"includePromotedContent":false,"withQuickPromoteEligibilityTweetFields":false,"withVoice":true,"withV2Timeline":true}'
TWEETS_FEATURES='{"creator_subscriptions_tweet_preview_api_enabled":false,"communities_web_enable_tweet_community_results_fetch":false,"c9s_tweet_anatomy_moderator_badge_enabled":false,"articles_preview_enabled":false,"tweetypie_unmention_optimization_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"view_counts_everywhere_api_enabled":false,"longform_notetweets_consumption_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":false,"standardized_nudges_misinfo":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"tweet_with_visibility_results_prefer_gql_media_interstitial_enabled":false,"rweb_video_timestamps_enabled":false,"longform_notetweets_rich_text_read_enabled":false,"longform_notetweets_inline_media_enabled":false,"rweb_tipjar_consumption_enabled":false,"responsive_web_graphql_exclude_directive_enabled":false,"verified_phone_label_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_enhance_cards_enabled":false,"rweb_lists_timeline_redesign_enabled":false,"responsive_web_media_download_video_enabled":false}'

user_tweets=$(
  curl -sG "${TWEETS_URL}" "${HEADERS[@]}" \
    --data-urlencode "variables=${TWEETS_VARIABLES}" \
    --data-urlencode "features=${TWEETS_FEATURES}"
)

jq . <<< "${user_tweets}"

# simple save to file
#jq . <<< "${user_tweets}" > "${screen_name}-$EPOCHSECONDS.json" && echo Success

# output and save
#jq . <<< "${user_tweets}" | tee "${user_tweets_file}"

# just print if the timeline is sorted by likes or newest-first
#jq -r 'if (.data.user.result.timeline.timeline.instructions[-2].entries[0].content.clientEventInfo.component? == "profile_best_highlights")
#  then "[-] Sorted by \u001b[31mlikes\u001b[0m"
#  else "[+] Sorted by \u001b[32mrecency\u001b[0m"
#  end' <<< "${user_tweets}"
