#!/bin/bash
# Retrieve all users a Twitter account is following
# v1.1 now requires curl major_version >=8 or curl-impersonate
# TODO: fix for hidden/empty frienship entries

# provide `auth_token` and `x_csrf_token`
source ~/.env-twitter

usage() { echo "$0 twitter_username"; exit 1; }
[ "$#" -ne 1 ] && usage
screen_name="$1"

bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

# GetUser gql
url="https://x.com/i/api/graphql/1VOOyvKkiI3FMmkeDNxM9A/UserByScreenName"
variables='{"screen_name":"'"$screen_name"'","includePromotedContent":false,"withBirdwatchNotes":true,"withVoice":true}'
#api=https://x.com/i/api/graphql/laYnJPCAcVo0o6pzcnlVxQ/UserByScreenName
features='{"hidden_profile_subscriptions_enabled":true,"profile_label_improvements_pcf_label_in_post_enabled":true,"rweb_tipjar_consumption_enabled":true,"verified_phone_label_enabled":false,"subscriptions_verification_info_is_identity_verified_enabled":true,"subscriptions_verification_info_verified_since_enabled":true,"highlights_tweets_tab_ui_enabled":true,"responsive_web_twitter_article_notes_tab_enabled":true,"subscriptions_feature_can_gift_premium":true,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true}'
fieldToggles='{"withAuxiliaryUserLabels":true}'

lookup=$(curl -s -G "${header[@]}" $url \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" \
  --data-urlencode "fieldToggles=${fieldToggles}"
)
userId=$(jq -r '.data.user.result.rest_id' <<< "${lookup}")
screen_name=$(jq -r '.data.user.result.legacy.screen_name' <<< "${lookup}")
friends_count=$(jq -r '.data.user.result.legacy.friends_count' <<< "${lookup}")

# v1.1 max count was 200, gql seems to be 70 for first page, 50 thereafter
page_max=$(echo "${friends_count}/50" | bc)

dest=$screen_name

mkdir -p $dest

echo "*** Grabbing ${friends_count} handles (${page_max} pages)"
#exit

# Following gql
url="https://x.com/i/api/graphql/WJbdU-1ay4MHL8nKqCZYUQ/Following"
variables='{"userId":"'"${userId}"'","count":70,"includePromotedContent":false,"withGrokTranslatedBio":false}'
features='{"rweb_video_screen_enabled":false,"payments_enabled":false,"profile_label_improvements_pcf_label_in_post_enabled":false,"responsive_web_profile_redirect_enabled":false,"rweb_tipjar_consumption_enabled":false,"verified_phone_label_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"premium_content_api_read_enabled":false,"communities_web_enable_tweet_community_results_fetch":false,"c9s_tweet_anatomy_moderator_badge_enabled":false,"responsive_web_grok_analyze_button_fetch_trends_enabled":false,"responsive_web_grok_analyze_post_followups_enabled":false,"responsive_web_jetfuel_frame":false,"responsive_web_grok_share_attachment_enabled":false,"articles_preview_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"view_counts_everywhere_api_enabled":false,"longform_notetweets_consumption_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"tweet_awards_web_tipping_enabled":false,"responsive_web_grok_show_grok_translated_post":false,"responsive_web_grok_analysis_button_from_backend":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":false,"standardized_nudges_misinfo":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"longform_notetweets_rich_text_read_enabled":false,"longform_notetweets_inline_media_enabled":false,"responsive_web_grok_image_annotation_enabled":false,"responsive_web_grok_imagine_annotation_enabled":false,"responsive_web_grok_community_note_auto_translation_is_enabled":false,"responsive_web_enhance_cards_enabled":false}'

for f in $(seq 0 $page_max); do
  g=$(($f+1))
  cursor=$(jq -r '.data.user.result.timeline.timeline.instructions[-1] | if(.entries[-2].content.value) then (.entries[-2].content.value) else empty end' $dest/$f.json 2>/dev/null)
  after="\"cursor\":\"${cursor}\","
  if [[ $cursor != "null" ]]; then
      echo "Page $g [${cursor}]"
      variables='{"userId":"'"${userId}"'","count":50,'"${after}"'"includePromotedContent":false,"withGrokTranslatedBio":false}'
      curl -s -G "${header[@]}" $url -o $dest/$g.json \
        --data-urlencode "variables=${variables}" \
        --data-urlencode "features=${features}" \
        --data-urlencode "fieldToggles=${fieldToggles}"
    else
      break
  fi
done

friends_file=$screen_name-$(date '+%Y%m%d-%H%M%S').txt


cat $dest/*.json | jq '.data.user.result.timeline.timeline.instructions[-1].entries[] | select(.entryId | startswith("user-")) | .content.itemContent.user_results.result | "@\(.core.screen_name) (\(.core.name)) - \(.legacy.description)"' | sed 's|\\n\\n| |g;s|\\n| |g' | sed 's|^\"||;s|\"$||;s|\\||g;s|  | |g' | sort > $friends_file

echo "*** Saved @$screen_name following list of $friends_count users to $friends_file"
