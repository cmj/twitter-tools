#!/bin/bash
# Show current sessions

auth_token=$1
x_csrf_token=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)

if [[ -z $1 ]]; then echo "$0 <auth_token>"; exit 1; fi

curl -s 'https://x.com/i/api/graphql/vJ-XatpmQSG8bDch8-t9Jw/UserSessionsList?variables=%7B%7D' \
  -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:147.0) Gecko/20100101 Firefox/147.0' \
  -H "x-csrf-token: ${x_csrf_token}" \
  -H 'authorization: Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA' \
  -H "Cookie: auth_token=${auth_token}; ct0=${x_csrf_token}" |
  jq
