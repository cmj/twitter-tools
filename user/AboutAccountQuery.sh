#!/bin/bash
# Twitter "About" page

# requires auth_token.
#auth_token=""
source ~/.env-twitter
screen_name=$1

usage() { echo -e "Show Twitter account location (requires auth_token)\n $0 <screen_name>"; exit 1; }
[[ ! "$auth_token" || ! "$screen_name" ]] && usage

# generate random ct0
x_csrf_token=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)

####
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

api=https://x.com/i/api/graphql/qZ92r6KDO0_GZxVJGM33XA/AboutAccountQuery
variables='{"screenName":"'"${screen_name}"'"}'


#### pretty print
curl -s -G "${header[@]}" $api \
  --data-urlencode "variables=${variables}" |
  jq -r '.data.user_result_by_screen_name.result | "\(.core.screen_name) (\(.core.name)) | created: \(.core.created_at) | based in: \(.about_profile.account_based_in) | source: \(.about_profile.source) | accuracy (false=vpn): \(.about_profile.location_accurate)"'

