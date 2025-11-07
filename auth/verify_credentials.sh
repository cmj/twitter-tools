#!/bin/bash
# Twitter API verify_credentials/is_logged_in example  

auth_token=$1

#x_csrf_token=''
# or basic csrf token. this 32-byte string can be random, unlike the
# 160-byte x-csrf-token you are given.
x_csrf_token='00000000000000000000000000000000' 

bearer_token="AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF"

curl -s \
  -H "Authorization: Bearer ${bearer_token}" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" \
  -H "X-Csrf-Token: ${x_csrf_token}" \
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}" \
  'https://api.twitter.com/1.1/account/verify_credentials.json' |
  jq
