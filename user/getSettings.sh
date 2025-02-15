#!/bin/bash
# Get account settings

auth_token=$1

###
ct0=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)
bearer_token=AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF
#bearer_token=AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA

curl https://api.x.com/1.1/account/settings.json \
  -H "x-csrf-token: ${ct0}" \
  -H "authorization: Bearer ${bearer_token}" \
  -H "Cookie: ct0=${ct0}; auth_token=${auth_token}"
