#!/bin/bash
# grab twitter user info
# requires account, 2 parameters from header

x_csrf_token=""
auth_token=""

usage() { echo "$0 username"; exit 1; }
[ "$#" -ne 1 ] && usage
user="$1"

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'

curl -s "https://api.twitter.com/1.1/users/lookup.json?screen_name=${user//@/}" \
  -H "Authorization: Bearer ${bearer_token}" \
  -H "X-Csrf-Token: ${x_csrf_token}" \
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}" | jq 

#jq -r '.[] | "\(.screen_name) (\(.name)) | \(.description) | tw: \(.statuses_count) | fr: \(.friends_count) |fol: \(.followers_count)| loc: \(.location) | id: \(.id_str) | \(.created_at) | \(.entities.url.urls[0].expanded_url)"'

