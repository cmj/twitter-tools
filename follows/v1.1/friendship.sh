#!/bin/bash

usage() { echo -e "See friendship between users\n$0 source_username target_username"; exit 1; }
[ "$#" -ne 2 ] && usage
source="$1"
target="$2"

bearer_token='AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
#user_agent="TwitterAndroid/10.21.1"
user_agent="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:146.0) Gecko/20100101 Firefox/146.0"

curl -s "https://api.x.com/1.1/friendships/show.json?source_screen_name=${source//@/}&target_screen_name=${target//@/}" \
  -H "Authorization: Bearer ${bearer_token}" \
  -H "User-Agent: ${user_agent}" |
  jq -r 'if(.relationship) then .relationship | "@\(.source.screen_name) follows @\(.target.screen_name): \(.source.following) | followed by @\(.target.screen_name): \(.source.followed_by)" else .errors[0].message end'
