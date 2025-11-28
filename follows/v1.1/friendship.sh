#!/bin/bash
# v1.1 now requires curl major_version >=8 or curl-impersonate

usage() { echo -e "See friendship between users\n$0 source_username target_username"; exit 1; }
[ "$#" -ne 2 ] && usage
source="$1"
target="$2"

bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'

curl -s -H "Authorization: Bearer ${bearer_token}" \
  "https://api.x.com/1.1/friendships/show.json?source_screen_name=${source//@/}&target_screen_name=${target//@/}" |
  jq -r '.relationship | "@\(.source.screen_name) follows @\(.target.screen_name): \(.source.following) | followed by @\(.target.screen_name): \(.source.followed_by)"'
