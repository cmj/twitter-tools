#!/bin/bash
# Grab all raw tweets and replies from user timeline
# Requires Twitter account, 2 parameters from header

x_csrf_token=''
auth_token=''

####

usage() { echo "$0 username"; exit 1; }
[ "$#" -ne 1 ] && usage
user="$1"

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Twitterbot" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

lookup=$(curl -s "https://api.twitter.com/1.1/users/lookup.json?screen_name=${user//@/}" "${header[@]}")
user_id=$(jq '.[].id' <<< "${lookup}")
screen_name=$(jq -r '.[].screen_name' <<< "${lookup}")
statuses_count=$(jq '.[].statuses_count' <<< "${lookup}")
page_max=$(echo "${statuses_count}/20" | bc)

dest=$screen_name

api='https://x.com/i/api/graphql/bt4TKuFz4T7Ckk-VvQVSow/UserTweetsAndReplies'
variables='{"userId":"'"${user_id}"'","count":200,"includePromotedContent":false,"withCommunity":true,"withVoice":true,"withV2Timeline":true}'
features='{"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":false,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"rweb_video_timestamps_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"responsive_web_enhance_cards_enabled":false}'
fieldToggles='{"withArticlePlainText":true}'

statuses_count=$(jq '.[].statuses_count' <<< "${lookup}")
page_max=$(echo "${statuses_count}/20" | bc)
#page_max=4

dest=$screen_name

mkdir -p $dest

echo "*** Grabbing $statuses_count tweets and replies ($((page_max+1)) pages) from @${screen_name}"

for f in $(seq 0 $page_max); do
  g=$(($f+1)) 
  after=$(jq -r '"\"cursor\":\"\(.data.user.result.timeline_v2.timeline.instructions[-1].entries[-1].content.value)\","' $dest/$f.json 2>/dev/null)
  if [ -z $after ] || [[ $after != "null" ]]; then
      variables='{"userId":"'"${user_id}"'","count":20,'"${after}"'"includePromotedContent":false,"withCommunity":true,"withVoice":true,"withV2Timeline":true}'
      echo "Page $g [${after//*=/cursor }]"
      curl -s -G "${header[@]}" "${api}" -o $dest/$g.json \
        --data-urlencode "variables=${variables}" \
        --data-urlencode "features=${features}" \
        --data-urlencode "fieldToggles=${fieldToggles}"
      date_range=$(jq -r '.data.user.result.timeline_v2.timeline.instructions[-1] | "\(.entries[0].content.itemContent.tweet_results.result.legacy.created_at) - \(.entries[-3].content.itemContent.tweet_results.result.legacy.created_at)"' $dest/$g.json 2>/dev/null)
      echo "$date_range"
    else
      break
  fi
done
