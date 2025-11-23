#!/bin/bash
# Twitter "For You" timeline

auth_token=$1

usage() { echo -e "Print \"for you\" timeline\n$0 auth_token"; exit 1; }
[ ! "$auth_token" ] && usage

# generate random ct0
x_csrf_token=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)

####
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

api=https://x.com/i/api/graphql/qIWNRQfRx-Rq2ybMont8rQ/HomeTimeline
variables='{"count":20,"includePromotedContent":true,"latestControlAvailable":true,"requestContext":"launch","withCommunity":true}'
features='{"rweb_video_screen_enabled":false,"profile_label_improvements_pcf_label_in_post_enabled":true,"responsive_web_profile_redirect_enabled":false,"rweb_tipjar_consumption_enabled":true,"verified_phone_label_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"premium_content_api_read_enabled":false,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"responsive_web_grok_analyze_button_fetch_trends_enabled":false,"responsive_web_grok_analyze_post_followups_enabled":true,"responsive_web_jetfuel_frame":true,"responsive_web_grok_share_attachment_enabled":true,"articles_preview_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"responsive_web_grok_show_grok_translated_post":true,"responsive_web_grok_analysis_button_from_backend":true,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"responsive_web_grok_image_annotation_enabled":true,"responsive_web_grok_imagine_annotation_enabled":true,"responsive_web_grok_community_note_auto_translation_is_enabled":false,"responsive_web_enhance_cards_enabled":false}'


#### pretty print
curl -s -G "${header[@]}" $api \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq '.data.home.home_timeline_urt.instructions[0].entries[].content.itemContent.tweet_results | select(.result) | .result | "@\(.core.user_results.result.core.screen_name) (\(.core.user_results.result.core.name))\(if(.core.user_results.result.core.verified_type == "Business") then "GOLD✔: " elif(.core.user_results.result.core.verified_type == "Government") then "GOV✔: " elif(.core.user_results.result.is_blue_verified == true) then "BLUE✔: " else ": " end)\(.legacy.full_text | gsub("&amp;";"&") | gsub("  ";" "))\(if(.quoted_status_result) then (.quoted_status_result.result |" [@\(.core.user_results.result.core.screen_name)] \(.legacy.full_text)") else "" end)\(if(.legacy.extended_entities.media) then " [\(.legacy.extended_entities.media.[0].type)\(if([.legacy.extended_entities.media.[]]|length >= 2) then "s" else "" end)]" else "" end)  | ↳ \(.legacy.reply_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")) ⇅\(.legacy.retweet_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",")) ♥ \(.legacy.favorite_count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse| join(",")) 🡕 \(if(.views.count) then "\(.views.count | tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(","))" else "" end) | \(.source | gsub("<[^>]*>";"")) \(if(.core.user_results.result.location.location != "") then "| \(.core.user_results.result.location.location) " else "" end)\(if(.has_birdwatch_notes == true) then "| birdwatch " else "" end)| https://x.com/_/status/\(.legacy.id_str)"' |
    sed 's/\\n/ /g;s/^\"//;s/\"$//'

