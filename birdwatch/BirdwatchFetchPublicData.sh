#!/bin/bash
# Fetch Birdwatch (Community Notes) public data archive resources.
# Lag of a few days before archiving.

auth_token=$AUTH_TOKEN

####
x_csrf_token=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")
api=https://x.com/i/api/graphql/9bDdJ6AL26RLkcUShEcF-A/BirdwatchFetchPublicData
variables='{}'
features='{}'
curl -s -G "${header[@]}" $api \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq 
