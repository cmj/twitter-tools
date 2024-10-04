#!/bin/bash

usage() { echo -e "See friendship between users\n$0 source_username target_username"; exit 1; }
[ "$#" -ne 2 ] && usage
source="$1"
target="$2"

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'

curl -s -H "Authorization: Bearer ${bearer_token}" \
  "https://api.x.com/1.1/friendships/show.json?source_screen_name=${source//@/}&target_screen_name=${target//@/}" |
  jq -r '.relationship | "@\(.source.screen_name) follows @\(.target.screen_name): \(.source.following) | followed by @\(.target.screen_name): \(.source.followed_by)"'
