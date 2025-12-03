#!/bin/bash
# Grab latest tweets with proposed birdwatch notes
# doesn't always respond, may need to run a few times.

# source `auth_token` and `x_csrf_token`
if [ -f ~/.env-twitter ]; then
  . ~/.env-twitter
    if [[ -z $auth_token || -z $x_csrf_token ]]; then
      echo "set auth_token and x_csrf_token in .env-twitter"; exit 1
    fi
  else
    echo "set credentials in ~/.env-twitter"; exit 1
fi

#                  base64, strings extracted are: "Timeline: <user_id_>"
#     "birdwatch": "VGltZWxpbmU6CwA6AAAAEjcxMzgxNDUxOTEwNTk5ODg0OAA=",
#      "trending": "VGltZWxpbmU6DAC2CwABAAAACHRyZW5kaW5nAAA",
#          "news": "VGltZWxpbmU6DAC2CwABAAAABG5ld3MAAA",
#         "sport": "VGltZWxpbmU6DAC2CwABAAAABnNwb3J0cwAA",
# "entertainment": "VGltZWxpbmU6DAC2CwABAAAADWVudGVydGFpbm1lbnQAAA",
timeline_id="VGltZWxpbmU6CwA6AAAAEjcxMzgxNDUxOTEwNTk5ODg0OAA="

bearer_token="AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

url='https://x.com/i/api/graphql/jWHk--0VWuZ38aY2WDXUVA/GenericTimelineById'
variables='{"timelineId":"'"${timeline_id}"'","count":200,"withQuickPromoteEligibilityTweetFields":false}"'
features='{"rweb_video_screen_enabled":false,"payments_enabled":false,"profile_label_improvements_pcf_label_in_post_enabled":false,"rweb_tipjar_consumption_enabled":false,"verified_phone_label_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"premium_content_api_read_enabled":true,"communities_web_enable_tweet_community_results_fetch":false,"c9s_tweet_anatomy_moderator_badge_enabled":false,"responsive_web_grok_analyze_button_fetch_trends_enabled":false,"responsive_web_grok_analyze_post_followups_enabled":false,"responsive_web_jetfuel_frame":false,"responsive_web_grok_share_attachment_enabled":false,"articles_preview_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"view_counts_everywhere_api_enabled":false,"longform_notetweets_consumption_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"tweet_awards_web_tipping_enabled":false,"responsive_web_grok_show_grok_translated_post":false,"responsive_web_grok_analysis_button_from_backend":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":false,"standardized_nudges_misinfo":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"longform_notetweets_rich_text_read_enabled":false,"longform_notetweets_inline_media_enabled":false,"responsive_web_grok_image_annotation_enabled":false,"responsive_web_grok_imagine_annotation_enabled":false,"responsive_web_grok_community_note_auto_translation_is_enabled":false,"responsive_web_enhance_cards_enabled":false}"'

curl -s -G "${header[@]}" "${url}" \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq '[.data.timeline.timeline.instructions[-2].entries[].content.items[0].item.itemContent.tweet_results.result| select(.legacy.lang == "en")] | sort_by(.legacy.id_str)[] | "[\(.legacy.created_at | strptime("%a %b %d %H:%M:%S +0000 %Y") | mktime - (now | gmtime | mktime - (now | trunc)) | strflocaltime("%a %T"))] @\(.core.user_results.result.core.screen_name) | \(.legacy.full_text | gsub("\n\n";" ") | gsub("\n";"")) https://twitter.com/i/birdwatch/t/\(.legacy.id_str)"' | 
  jq -r | 
  column -l2 -s\| -t -o\│ |
  sed 's/\t/ /' |
  ct # colorterm
