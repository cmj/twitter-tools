#!/bin/bash
# 'Latest' Twitter search
# 
# $ ./search.sh from:nwsseattle snow
# @NWSSeattle (NWS Seattle): @Jiabiangou The snow has already melted in some areas on the north flank and that is exposed rock you are seeing. #wawx | ↳ 0 ⇅ 0 ♥ 1 🡕 175 | Twitter Web App | Seattle, WA | https://x.com/_/status/1810536393497870783 (1 month 1 day and 1 hours, 42 minutes ago)

x_csrf_token=''
auth_token=''
#source ~/.env-twitter

count=1 # 1-20
product=Latest # Latest | Top

####
if [[ -z "$x_csrf_token" || -z "$auth_token" ]]; then
  echo "requires x_csrf_token and auth_token"
  exit 1
fi

usage() { echo "$0 search query"; exit 1; }
[ ! "$*" ] && usage
input="$@"
query=$(perl -MURI::Escape -wlne 'print uri_escape $_' <<< "${input}")

bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'

#URL='https://x.com/i/api/graphql/UN1i3zUiCWa-6r-Uaho4fw/SearchTimeline'
URL='https://api.twitter.com/graphql/gkjsKepM6gl_HmFWoWKfgg/SearchTimeline'

VARIABLES="%7B%22rawQuery%22%3A%22${query}%22%2C%22count%22%3A${count}%2C%22product%22%3A%22${product}%22%2C%22withDownvotePerspective%22%3Afalse%2C%22withReactionsMetadata%22%3Afalse%2C%22withReactionsPerspective%22%3Afalse%7D"
#VARIABLES='{"rawQuery":"'"${query}"'","count":1,"querySource":"typed_query","product":"Latest"}'

FEATURES='{"android_graphql_skip_api_media_color_palette":false,"blue_business_profile_image_shape_enabled":false,"creator_subscriptions_subscription_count_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"freedom_of_speech_not_reach_fetch_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"hidden_profile_likes_enabled":false,"highlights_tweets_tab_ui_enabled":false,"interactive_text_enabled":false,"longform_notetweets_consumption_enabled":true,"longform_notetweets_inline_media_enabled":false,"longform_notetweets_richtext_consumption_enabled":true,"longform_notetweets_rich_text_read_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"responsive_web_enhance_cards_enabled":false,"responsive_web_graphql_exclude_directive_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_media_download_video_enabled":false,"responsive_web_text_conversations_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"responsive_web_twitter_blue_verified_badge_is_enabled":true,"rweb_lists_timeline_redesign_enabled":true,"spaces_2022_h2_clipping":true,"spaces_2022_h2_spaces_communities":true,"standardized_nudges_misinfo":false,"subscriptions_verification_info_enabled":true,"subscriptions_verification_info_reason_enabled":true,"subscriptions_verification_info_verified_since_enabled":true,"super_follow_badge_privacy_enabled":false,"super_follow_exclusive_tweet_notifications_enabled":false,"super_follow_tweet_api_enabled":false,"super_follow_user_api_enabled":false,"tweet_awards_web_tipping_enabled":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"tweetypie_unmention_optimization_enabled":false,"unified_cards_ad_metadata_container_dynamic_card_content_query_enabled":false,"verified_phone_label_enabled":false,"vibe_api_enabled":false,"view_counts_everywhere_api_enabled":false}'

header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

# --data-urlencode "variables=${VARIABLES}" \
out=$(curl -sG "${URL}" "${header[@]}" \
  -d "variables=${VARIABLES}" \
  --data-urlencode "features=${FEATURES}")

############
# fancy output
tw=$(jq -r '.data.search_by_raw_query.search_timeline.timeline.instructions[0].entries[0].content.itemContent.tweet_results.result | "@\(.core.user_results.result.legacy.screen_name) (\(.core.user_results.result.legacy.name))\(if(.core.user_results.result.legacy.verified_type == "Business") then "【𝗚】: " elif(.core.user_results.result.is_blue_verified == true) then "【𝗕】: " else ": " end)\(.legacy.full_text | gsub("&amp;";"&") | gsub("  ";" ")) | ↳ \(.legacy.reply_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")) ⇅ \(.legacy.retweet_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")) ♥ \(.legacy.favorite_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")) 🡕 \(if(.views.count) then "\(.views.count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(","))" else "" end) | \(.source | gsub("<[^>]*>";"")) \(if(.core.user_results.result.legacy.location != "") then "| \(.core.user_results.result.legacy.location) " else "" end)\(if(.has_birdwatch_notes == true) then "| 𝚑𝚊𝚜 𝚋𝚒𝚛𝚍𝚠𝚊𝚝𝚌𝚑 𝚗𝚘𝚝𝚎 " else "" end)| https://nitter.net/_/status/\(.legacy.id_str)"' <<< $out 2>/dev/null | sed -e ':a;N;$!ba;s/\n/ /g' -e 's/  / /g;s/\&amp;/\&/g' 2>/dev/null)

ts=$(jq -r '.data.search_by_raw_query.search_timeline.timeline.instructions[0].entries[0].content.itemContent.tweet_results.result.legacy.created_at' <<< $out 2>/dev/null)

if [ -z "$tw" ]; then
    echo not found
  else
    datetime=$(dateutils.ddiff -i '%a %b %d %T +0000 %Y' "${ts}" now -f  ' %y years %m months %d days and %H hours, %M minutes ago' |sed 's/ 0 years/ /;s/ 1 years/ 1 year/;s/ 0 months/ /;s/ 1 months/ 1 month/;s/ 0 days/ /;s/ 1 days/ 1 day/;s/^[ ]*//;s/months.*/months ago/;s/^and //;s/^0 hours, //;s/^1 hours/1 hour/' 2>/dev/null)
    echo "$tw ($datetime)"
fi
