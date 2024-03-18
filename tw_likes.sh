#!/bin/bash
# grab the last ~100 (hidden) likes from a twitter user
# requires account, 2 parameters from header

x_csrf_token='XXXXXXXXXX'
auth_token='XXXXXXXXXX'

####

usage() { echo "$0 username"; exit 1; }
[ "$#" -ne 1 ] && usage
user="$1"

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'

user_id=$(curl -s "https://twitter.com/i/api/graphql/SAMkL5y_N9pmahSw8yy6gw/UserByScreenName?variables=%7B%22screen_name%22%3A%22${user}%22%2C%22withSafetyModeUserFields%22%3Atrue%7D&features=%7B%22responsive_web_twitter_blue_verified_badge_is_enabled%22%3Atrue%2C%22responsive_web_graphql_exclude_directive_enabled%22%3Afalse%2C%22verified_phone_label_enabled%22%3Afalse%2C%22responsive_web_graphql_skip_user_profile_image_extensions_enabled%22%3Afalse%2C%22responsive_web_graphql_timeline_navigation_enabled%22%3Atrue%2C%22hidden_profile_subscriptions_enabled%22%3Atrue%2C%22highlights_tweets_tab_ui_enabled%22%3Atrue%2C%22hidden_profile_likes_enabled%22%3Atrue%2C%22subscriptions_verification_info_is_identity_verified_enabled%22%3Atrue%2C%22subscriptions_verification_info_verified_since_enabled%22%3Atrue%2C%22creator_subscriptions_tweet_preview_api_enabled%22%3Atrue%7D" \
  -H "Authorization: Bearer $bearer_token" \
  -H "X-Csrf-Token: $x_csrf_token" \
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}" | \
  jq -r '.data.user.result.rest_id')

# paginate with max_id=<.id_str[-1]>
curl -s "https://api.twitter.com/1.1/favorites/list.json?count=100&include_my_retweet=true&user_id=${user_id}&cards_platform=Web-13&include_entities=true&include_user_entities=true&include_cards=true&send_error_codes=true&tweet_mode=extended&include_ext_alt_text=true&include_reply_count=true" \
  -H "Authorization: Bearer $bearer_token" \
  -H "X-Csrf-Token: $x_csrf_token" \
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}" | \
  jq

#  tee -a incoming.out | \
#  fx
