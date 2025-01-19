#!/bin/bash
# Spaces search - return list of Live audio feeds matching search query
# ./xSpacesLive football
# Use mpv, vlc, etc., to play streams

filter="Top" # [Live|Top]
limit=5 # limit results

# source x_csrf_token and auth_token
. ~/.env-twitter

query="$@"

####

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: TwitterAndroid/10.21.1" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

url='https://x.com/i/api/graphql/NTq79TuSz6fHj8lQaferJw/AudioSpaceSearch'
variables='{"query":"'"${query}"'","filter":"'"${filter}"'"}'
features='{"creator_subscriptions_tweet_preview_api_enabled":true,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"rweb_video_timestamps_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_enhance_cards_enabled":false}'

sp_url='https://x.com/i/api/graphql/p8k4kaPusjNj85gj8w_YAQ/AudioSpaceById'
sp_features='{"spaces_2022_h2_spaces_communities":true,"spaces_2022_h2_clipping":true,"creator_subscriptions_tweet_preview_api_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"rweb_video_timestamps_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_enhance_cards_enabled":false}'

audio_url() {
  media_id=$1
  url="https://x.com/i/api/1.1/live_video_stream/status/${media_id}"
  curl -s "${header[@]}" "${url}" | jq -r .source.noRedirectPlaybackUrl
}

spaces() {
  id=$1
  sp_variables='{"id":"'"${id}"'","isMetatagsQuery":false,"withReplays":true,"withListeners":true}'
  space_by_id=$(curl -s -G "${header[@]}" "${sp_url}" \
    --data-urlencode "variables=${sp_variables}" \
    --data-urlencode "features=${sp_features}" )
    jq -r '.data.audioSpace | "\(.metadata.title) | Users: \(.participants.total) | \(.metadata.media_key) | Host: @\(.metadata.creator_results.result.legacy.screen_name) (\(.metadata.creator_results.result.legacy.name)) | Admins: \([.participants.admins[] | "@\(.twitter_screen_name)"] | join(" - ")) | Speakers: \([.participants.speakers[] | "@\(.twitter_screen_name)"] | join(" "))\nListeners: \([.participants.listeners[] | "@\(.twitter_screen_name)"] | join(" "))"' <<< "${space_by_id}"
    media_key=$(jq -r .data.audioSpace.metadata.media_key <<< "${space_by_id}")
    audio_url "${media_key}"
}

curl -s -G "${header[@]}" $url \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq -r '.data.search_by_raw_query.audio_spaces_grouped_by_section | if(.sections[0].items[]) then .sections[0].items[].space.rest_id else empty end' |
  head -$limit |
  while read id; do
    echo "# Space - $id"
    spaces "${id}"
  done #| ct # chromaterm 
