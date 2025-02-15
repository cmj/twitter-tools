#!/bin/bash
# Enable NSFW/sensitive media in account settings 
# follow up to verify settings

auth_token=$1

###
ct0=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)
#bearer_token="AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
bearer_token="AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF"

curl -s https://api.x.com/1.1/account/settings.json \
  -H "x-csrf-token: ${ct0}" \
  -H "authorization: Bearer ${bearer_token}" \
  -H "Cookie: ct0=${ct0}; auth_token=${auth_token}" \
  -d 'include_mention_filter=true&include_nsfw_user_flag=true&include_nsfw_admin_flag=true&include_ranked_timeline=true&include_alt_text_compose=true&display_sensitive_media=true'
