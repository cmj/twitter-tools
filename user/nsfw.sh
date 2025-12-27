#!/bin/bash
# Enable NSFW/sensitive media in account settings 
# follow up to verify settings

auth_token=$1

if [[ -z $1 ]]; then echo -e "Enable sensitive content\n$0 <auth_token>"; exit 1; fi

###
ct0=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)
bearer_token="AAAAAAAAAAAAAAAAAAAAAIWCCAAAAAAA2C25AxqI%2BYCS7pdfJKRH8Xh19zA%3D8vpDZzPHaEJhd20MKVWp3UR38YoPpuTX7UD2cVYo3YNikubuxd"

curl -s https://api.x.com/1.1/account/settings.json \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" \
  -H "x-csrf-token: ${ct0}" \
  -H "authorization: Bearer ${bearer_token}" \
  -H "Cookie: ct0=${ct0}; auth_token=${auth_token}" \
  -d 'include_mention_filter=true&include_nsfw_user_flag=true&include_nsfw_admin_flag=true&include_ranked_timeline=true&include_alt_text_compose=true&display_sensitive_media=true' |
  jq
