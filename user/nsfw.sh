#!/bin/bash
# Enable NSFW/sensitive media in account settings 
# follow up to verify settings

auth_token=$1

if [[ -z $1 ]]; then echo -e "Enable sensitive content\n$0 <auth_token>"; exit 1; fi

###
ct0=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)
bearer_token="AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"

curl -s https://api.x.com/1.1/account/settings.json \
  -H "User-Agent: TwitterAndroid/10.21.1" \
  -H "x-csrf-token: ${ct0}" \
  -H "authorization: Bearer ${bearer_token}" \
  -H "Cookie: ct0=${ct0}; auth_token=${auth_token}" \
  -d 'include_mention_filter=true&include_nsfw_user_flag=true&include_nsfw_admin_flag=true&include_ranked_timeline=true&include_alt_text_compose=true&display_sensitive_media=true' |
  jq
