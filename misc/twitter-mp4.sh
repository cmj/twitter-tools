#!/bin/bash
# grab twitter mp4 that requires auth

input="$1"

#auth_token=""
# or source env file
. ~/.env-twitter
x_csrf_token=$(openssl rand -hex 16) # ct0

if [[ -z "$x_csrf_token" || -z "$auth_token" ]]; then echo "requires x_csrf_token and auth_token"; exit 1; fi
if [[ -z "$input" ]]; then echo "usage: ${0##*/} <full_mp4_url>"; exit 1; fi

bearer_token="AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

curl -O "${header[@]}" "${input}"

