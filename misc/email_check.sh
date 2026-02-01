#!/usr/bin/env bash
# Twitter email check
# ./email_check.sh erm@spacex.com
# {"valid":false,"msg":"Email has already been taken.","taken":true}

email=$1

#auth_token=""
# source for auth_token
. ~/.env-twitter

x_csrf_token=$(openssl rand -hex 16)

if [[ -z "$auth_token" || -z "$email" ]]; then echo "Usage: $0 email@example.com (requires auth_token)"; exit 1; fi

bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'

headers=(
  -H "Authorization: Bearer ${bearer_token}"
  -H "User-Agent: TwitterAndroid/10.21.1"
  -H "X-Csrf-Token: ${x_csrf_token}"
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}"
)

curl -s "${headers[@]}" "https://api.x.com/i/users/email_available.json?email=${email/@/%40}" | jq -c


