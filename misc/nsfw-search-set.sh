#!/bin/bash
# Unset "Hide sensitive content" in search settings
# 
#  "optInFiltering": false, <- don't filter NSFW from search
#  "optInBlocking": true    <- remove blocked accounts from search

auth_token=$1

###
ct0=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)
bearer_token=AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F

headers=(
  -H "Authorization: Bearer ${bearer_token}" \
  -H "User-Agent: TwitterAndroid/10.21.1" \
  -H "x-csrf-token: ${ct0}" \
  -H "cookie: ct0=${ct0}; auth_token=${auth_token}"
)

verify() {
  curl -s "${headers[@]}" "https://api.x.com/1.1/account/verify_credentials.json?include_email=true&skip_status=false&include_entities=true"
}

user_id=$(verify | jq -r .id)

curl -s "${headers[@]}" "https://x.com/i/api/1.1/strato/column/User/${user_id}/search/searchSafety" \
  -d '{"optInFiltering":false,"optInBlocking":true}'
