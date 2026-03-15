#!/bin/bash
text="test tweet"
#text=$(curl -s 'https://api.animechan.io/v1/quotes/random' | jq '.data.content[:100]')
#text=$(curl -s 'https://zenquotes.io/api/quotes/keyword=happiness' | jq '.[0].q[:100]')
source=android # android | iphone | mac | ipad (403) | web (fails with limit/automated error) 

###

if [[ ! -f cookies.json ]]; then echo "Requires valid cookies.json"; exit 1; fi

url="https://x.com/i/api/graphql/SwEFc8z18gL1ahel3VSIow/CreateTweet" # x 2026-03-10
ct0=$(jq -r .ct0 cookies.json)
cookie=$(jq -r 'to_entries | map("\(.key)=\(.value)") | join("; ")' cookies.json)
data='{"variables":{"tweet_text":"'"${text}"'","media":{"media_entities":[],"possibly_sensitive":false},"semantic_annotation_ids":[],"disallowed_reply_options":null},"features":{"premium_content_api_read_enabled":false,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"responsive_web_grok_analyze_button_fetch_trends_enabled":false,"responsive_web_grok_analyze_post_followups_enabled":true,"responsive_web_jetfuel_frame":true,"responsive_web_grok_share_attachment_enabled":true,"responsive_web_grok_annotations_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"content_disclosure_indicator_enabled":true,"content_disclosure_ai_generated_indicator_enabled":true,"responsive_web_grok_show_grok_translated_post":true,"responsive_web_grok_analysis_button_from_backend":true,"post_ctas_fetch_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":false,"profile_label_improvements_pcf_label_in_post_enabled":true,"responsive_web_profile_redirect_enabled":false,"rweb_tipjar_consumption_enabled":false,"verified_phone_label_enabled":false,"articles_preview_enabled":true,"responsive_web_grok_community_note_auto_translation_is_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"responsive_web_grok_image_annotation_enabled":true,"responsive_web_grok_imagine_annotation_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_enhance_cards_enabled":false},"queryId":"SwEFc8z18gL1ahel3VSIow"}'

if [[ "$source" == android ]]; then
    curl_imp=curl_chrome99_android
    bearer_token="AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
    user_agent="TwitterAndroid/10.89.0-release.0 (310890000-r-0) G011A/9 (google;G011A;google;G011A;0;;1;2016)"
    #headers+=(-H "authorization: Bearer ${bearer_token}" -H "User-Agent: ${user_agent}")
  elif [[ "$source" == iphone ]]; then
    curl_imp=curl_safari15_5
    bearer_token="AAAAAAAAAAAAAAAAAAAAAAj4AQAAAAAAPraK64zCZ9CSzdLesbE7LB%2Bw4uE%3DVJQREvQNCZJNiz3rHO7lOXlkVOQkzzdsgu6wWgcazdMUaGoUGm"
    user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_7_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22H218 Twitter for iPhone/11.47"
  elif [[ "$source" == mac ]]; then
    curl_imp=curl_safari15_5
    bearer_token="AAAAAAAAAAAAAAAAAAAAAIWCCAAAAAAA2C25AxqI%2BYCS7pdfJKRH8Xh19zA%3D8vpDZzPHaEJhd20MKVWp3UR38YoPpuTX7UD2cVYo3YNikubuxd"
    user_agent="Mozilla/5.0 (iPad; CPU OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/24G512 Twitter for Mac/11.47"
  elif [[ "$source" == ipad ]]; then
    curl_imp=curl_safari15_5
    bearer_token="AAAAAAAAAAAAAAAAAAAAAGHtAgAAAAAA%2Bx7ILXNILCqkSGIzy6faIHZ9s3Q%3DQy97w6SIrzE7lQwPJEYQBsArEE2fC25caFwRBvAGi456G09vGR"
    user_agent="Mozilla/5.0 (iPad; CPU OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/24G512 Twitter for Mac/11.47"
  elif [[ "$source" == web ]]; then
    curl_imp=curl_ff117
    user_agent="Mozilla/5.0 (X11; Linux x86_64; rv:117.0) Gecko/20100101 Firefox/117.0"
    bearer_token="AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    path="${url##*x.com}"
    echo $path
    tid=$(curl -s "https://x-client-transaction-id-generator.xyz/generate-x-client-transaction-id?path=${path}" | jq -r '."x-client-transaction-id"')
    #headers+=(-H "x-client-transaction-id: ${tid}")
    tid_header='-H "x-client-transaction-id: '${tid}'"'
  else
    echo "Invalid source"
fi

headers=(
  -H "Host: x.com"
  -H "Accept: */*"
  -H "authorization: Bearer ${bearer_token}"
  -H "content-type: application/json"
  -H "X-Twitter-Auth-Type: OAuth2Session"
  -H "X-Twitter-Active-User: yes"
  -H "Referer: https://x.com/"
  -H "User-Agent: ${user_agent}"
  -H "Accept-Language: en-US"
  -H "X-Twitter-Client-Language: en-US"
  -H "X-Csrf-Token: ${ct0}"
  -H "Cookie: ${cookie}"
  ${tid_header}
)

$curl_imp -s "${headers[@]}" "${url}" -d "${data}" |
  jq -r '
    if .data.create_tweet then
      .data.create_tweet.tweet_results.result |
      "[\(.legacy.created_at)] \(.legacy.full_text) https://x.com/\(
        .core.user_results.result |
        .legacy.screen_name // .core.screen_name
      )/status/\(.legacy.id_str)"
    else
      .
    end
  '
