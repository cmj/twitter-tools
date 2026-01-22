#!/bin/bash
# Twitter API verify_credentials/is_logged_in with x-client-transaction-id
# This method is slower, only here as an example

auth_token=$1
x_csrf_token=$(openssl rand -hex 16)

if [[ -z "$auth_token" ]]; then echo "Usage: $0 auth_token"; exit 1; fi

bearer_token="AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
TID=$(curl -s "https://x-client-transaction-id-generator.xyz/generate-x-client-transaction-id?path=/1.1/account/verify_credentials.json" | jq -r '."x-client-transaction-id"')
curl -s \
  -H "Authorization: Bearer ${bearer_token}" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15" \
  -H "x-client-transaction-id: ${TID}" \
  -H "x-csrf-token: ${x_csrf_token}" \
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}" \
  'https://api.x.com/1.1/account/verify_credentials.json' |
  jq
