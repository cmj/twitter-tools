#!/bin/bash
# grab likes from an account using auth_token
# pretty print with chromaterm (ct)
# $ pipx install chromaterm

auth_token="$1"

#x_csrf_token=""
x_csrf_token="00000000000000000000000000000000"
#auth_token=""
#source .env

####
usage() { echo "$0 auth_token"; exit 1; }
[ "$#" -ne 1 ] && usage

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Twitterbot" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")
user_id=$(curl -s -G "${header[@]}" 'https://api.twitter.com/1.1/account/verify_credentials.json' | jq .id)

api=https://x.com/i/api/graphql/ChovsXvpiyWyXDQKbxaEkA/Likes
variables='{"userId":"'"${user_id}"'","count":200,"includePromotedContent":false,"withClientEventToken":false,"withBirdwatchNotes":false,"withVoice":true,"withV2Timeline":true}'
features='{"profile_label_improvements_pcf_label_in_post_enabled":false,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"rweb_video_timestamps_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"responsive_web_enhance_cards_enabled":false}'
fieldToggles='{"withArticlePlainText":false}'

curl -s -G "${header[@]}" "${api}" \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" \
  -data-urlencode "fieldToggles=${fieldToggles}" |
  jq '.data.user.result.timeline_v2.timeline.instructions[0].entries[].content.itemContent.tweet_results.result | select( . != null ) | "[\(.legacy.created_at)] Liked @\(.core.user_results.result.legacy.screen_name) - \(.legacy.full_text)  https://x.com/\(.core.user_results.result.legacy.screen_name)/status/\(.legacy.id_str)"' | sed 's/\\n/ /g;s/^\"//;s/\"$//;s/\\//g' | ct
