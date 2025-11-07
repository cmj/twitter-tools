#!/bin/bash
# grab twitter user info
# requires account, 2 parameters from header
# provide a valid auth_token (we can send a junk 32-byte csrf)

auth_token=""
x_csrf_token="00000000000000000000000000000000"

user=$1
if [[ -z $user || -z $auth_token ]]; then echo -e "provide an auth_token\n$0 user"; exit 1; fi

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'

curl -s "https://api.twitter.com/1.1/users/lookup.json?screen_name=${user//@/}" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" \
  -H "Authorization: Bearer ${bearer_token}" \
  -H "X-Csrf-Token: ${x_csrf_token}" \
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}" | jq 

#jq -r '.[] | "\(.screen_name) (\(.name)) | \(.description) | tw: \(.statuses_count) | fr: \(.friends_count) |fol: \(.followers_count)| loc: \(.location) | id: \(.id_str) | \(.created_at) | \(.entities.url.urls[0].expanded_url)"'

