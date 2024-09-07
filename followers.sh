#!/bin/bash

x_csrf_token=''
auth_token=''

usage() { echo "$0 twitter_username"; exit 1; }
[ "$#" -ne 1 ] && usage
user="$1"

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: TwitterAndroid/10.21.1" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

lookup=$(curl -s "https://api.twitter.com/1.1/users/lookup.json?screen_name=${user//@/}" "${header[@]}")
user_id=$(jq '.[].id' <<< "${lookup}")
screen_name=$(jq -r '.[].screen_name' <<< "${lookup}")
followers_count=$(jq '.[].followers_count' <<< "${lookup}") 
page_max=$(echo "${followers_count}/200" | bc)

dest=$screen_name-followers

mkdir -p $dest

echo "*** Grabbing $followers_count handles"

for f in $(seq 0 $page_max); do
  g=$(($f+1))
  after=$(jq -r '"&cursor=\(.next_cursor)"' $dest/$f.json 2>/dev/null)
  if [ -z $after ] || [[ $after != "null" ]]; then
      echo "Page $g [${after//*=/cursor }]"
      #curl -s "${header[@]}" -o $dest/$g.json "https://api.twitter.com/1.1/friends/list.json?count=200&include_my_retweet=1${after}&user_id=${user_id}&cards_platform=Web-13&include_entities=1&include_user_entities=1&include_cards=1&send_error_codes=1&tweet_mode=extended&include_ext_alt_text=true&include_reply_count=true"
      curl -s "${header[@]}" -o $dest/$g.json "https://api.twitter.com/1.1/followers/list.json?screen_name=${screen_name}&count=200${after}&cards_platform=Web-13&include_entities=1&include_user_entities=1&include_cards=1&send_error_codes=1&tweet_mode=extended&include_ext_alt_text=true&include_reply_count=true"
      #sleep 1
    else
      break
  fi
done

followers_file=$screen_name-followers-$(date '+%Y%m%d-%H%M%S').txt

# simple
#cat $dest/*.json | jq -r '.users[] | "@\(.screen_name) (\(.name))"' | sort > $friends_file

# extended
cat $dest/*.json | jq  '.users[] | "@\(.screen_name) (\(.name)) - \(.description)"' |  sed 's|\\n\\n| |g;s|\\n| |g' | sed 's|^\"||;s|\"$||;s|\\||g;s|  | |g' | sort > $followers_file

echo "*** Saved @$screen_name followers list of $followers_count users to $followers_file"
