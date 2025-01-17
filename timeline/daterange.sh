#!/bin/bash
# Grab all tweets from user search between a date range
# ./script screen_name since_date until_date (in YYYY-MM-DD format) 
# x-rate-limit counters shown (1200 requests every 15mins) 

auth_token=""

####

x_csrf_token=$(tr -dc 0-9a-f < /dev/urandom | head -c 32) # just make this up
product="Latest" # Latest | Top 
interval=0 # sleep n seconds between requests

####

usage() { echo "$0 username since until [from date - to date, in YYYY-MM-DD format]"; exit 1; }; [ "$#" -ne 3 ] && usage
user="$1"
since="$2"
until="$3"
dest="${user}-${since}_${until}"

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: TwitterAndroid/10.21.1" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

query="from:${user} since:${since} until:${until}"

#url='https://api.twitter.com/graphql/gkjsKepM6gl_HmFWoWKfgg/SearchTimeline'
url='https://x.com/i/api/graphql/uGjEfWQSYF3MLxu5TVEiRA/SearchTimeline'
variables='{"rawQuery":"'"${query}"'","count":200,"querySource":"typed_query","product":"Latest"}'
features='{"android_graphql_skip_api_media_color_palette":false,"blue_business_profile_image_shape_enabled":false,"creator_subscriptions_subscription_count_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"freedom_of_speech_not_reach_fetch_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"hidden_profile_likes_enabled":false,"highlights_tweets_tab_ui_enabled":false,"interactive_text_enabled":false,"longform_notetweets_consumption_enabled":true,"longform_notetweets_inline_media_enabled":false,"longform_notetweets_richtext_consumption_enabled":true,"longform_notetweets_rich_text_read_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"responsive_web_enhance_cards_enabled":false,"responsive_web_graphql_exclude_directive_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_media_download_video_enabled":false,"responsive_web_text_conversations_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"responsive_web_twitter_blue_verified_badge_is_enabled":true,"rweb_lists_timeline_redesign_enabled":true,"spaces_2022_h2_clipping":true,"spaces_2022_h2_spaces_communities":true,"standardized_nudges_misinfo":false,"subscriptions_verification_info_enabled":true,"subscriptions_verification_info_reason_enabled":true,"subscriptions_verification_info_verified_since_enabled":true,"super_follow_badge_privacy_enabled":false,"super_follow_exclusive_tweet_notifications_enabled":false,"super_follow_tweet_api_enabled":false,"super_follow_user_api_enabled":false,"tweet_awards_web_tipping_enabled":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"tweetypie_unmention_optimization_enabled":false,"unified_cards_ad_metadata_container_dynamic_card_content_query_enabled":false,"verified_phone_label_enabled":false,"vibe_api_enabled":false,"view_counts_everywhere_api_enabled":true,"responsive_web_grok_analyze_button_fetch_trends_enabled":true,"creator_subscriptions_quote_tweet_preview_enabled":false,"profile_label_improvements_pcf_label_in_post_enabled":false,"rweb_tipjar_consumption_enabled":true,"rweb_video_timestamps_enabled":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"communities_web_enable_tweet_community_results_fetch":true,"premium_content_api_read_enabled":false,"articles_preview_enabled":true,"responsive_web_grok_analyze_post_followups_enabled":false}'

mkdir -p $dest
start=$EPOCHSECONDS
count=0
#################
while :; do
  next=$(($count+1))
  header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: TwitterAndroid/10.21.1" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")
  cursor=$(jq -r '.data.search_by_raw_query.search_timeline.timeline.instructions[-1] | if(.entries[-1].content.value) then .entries[-1].content.value else .entry.content.value end' $dest/$count.json 2>/dev/null)
  after="\"cursor\":\"${cursor}\","
  if [[ $cursor != "null" ]]; then # XXX getting cursors on empty reults with search api
      variables='{"rawQuery":"'"${query}"'","count":20,'"${after}"'"querySource":"typed_query","product":"'"${product}"'"}'  
      if [ -z "${cursor}" ]; then cursor="First page"; fi
      echo -e "page \x1b[40m $next \x1b[0m [${cursor}]"
      
      # grab headers (-i) to get x-rate-limits
      fetch=$(curl -si -G "${header[@]}" "${url}" --data-urlencode "variables=${variables}" --data-urlencode "features=${features}")
      tail -1 <<< "${fetch}" > $dest/$next.json
      
      # XXX count tweets in response, if none then exit (this doesn't always work) 
      if [[ $(jq -r '.data.search_by_raw_query.search_timeline.timeline.instructions[0] | if(.entries) then([.entries[]]|length) else 0 end' $dest/$next.json 2>/dev/null) -eq 0 ]]; then
        end=$EPOCHSECONDS
        echo "✨ All done - completed in $(($end-$start)) seconds"
        tweet_count=$(cat $dest/*.json | jq '.data.search_by_raw_query.search_timeline.timeline.instructions[0] | if(.entries) then ([.entries[]]|length) else 0 end' | awk '{sum+=$1};END{printf(sum)}')
        echo "Downloaded ${tweet_count} tweets from @${user} between ${since} - ${until} to ${dest}/"
        exit 0
      fi

      # print date range of first-last tweet of query 
      date_range=$(jq -r '[.data.search_by_raw_query.search_timeline.timeline.instructions[0].entries[] | select(.entryId | startswith("tweet-")) | .content.itemContent.tweet_results.result.legacy.created_at][0,-1] | sub(" \\+0000";"")' $dest/$next.json 2>/dev/null | sed -z 's/\n/ <----> /')
      rate_limits=$(sed -En -e 's/^x-rate-limit-.*: (.*)\r/\1/p' <<< "${fetch}" | sort -n | xargs | while read remaining limit reset; do echo -e "\x1b[32m${remaining}/${limit}\x1b[0m reset: \x1b[94m$(date -d@$reset '+%a %T')\x1b[0m"; done)

      echo -e "\x1b[1;96m${date_range}\x1b[0m | x-rate-limit: ${rate_limits}" #| ct # chromaterm
      
      #if [[ $token -lt $tokens_max ]]; then
      #    ((token++))
      #  else
      #    token=0
      #fi
      
      ((count++))
      sleep $interval
    else
      echo "### END"
      break
  fi
done

