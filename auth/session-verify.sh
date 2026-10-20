#!/bin/bash
# Twitter API verify_credentials/isLoggedIn check for single auth_token
# or for nitter sessions.jsonl file

pretty() {
  jq -r '
    ((.screen_name? // "")
     + (if (((.errors | arrays) // []) | any(.message? != null)) then "invalid" else "" end)
     + " "
     + (if .suspended == true then "\u001b[31mSUSPENDED\u001b[0m"
        elif .suspended == false then "\u001b[35mvalid\u001b[0m"
        else "" end)
    ) | select(length > 0)
  '
}

verify() {
  bearer_token="AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
  url="https://api.twitter.com/1.1/account/verify_credentials.json"
  user_agent="TwitterAndroid/10.53.2-release.0 (310532000-r-0)"
  curl -sG "${url}" \
    -H "Authorization: Bearer ${bearer_token}" \
    -H "User-Agent: ${user_agent}" \
    -H "X-Csrf-Token: ${ct0}" \
    -H "Cookie: ct0=${ct0}; auth_token=${auth_token}" \
    --data-urlencode "include_email=true" \
    --data-urlencode "skip_status=true" \
    --data-urlencode "include_entities=true"
}

raw=0
while getopts ":r" opt; do
  case "$opt" in
    r) raw=1 ;;
    *) echo "usage: $0 [-r] <40 character auth_token>"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

input=$1

if [[ "$input" == sessions.jsonl ]]; then
    jq -r '"\(.kind) \(.username) \(.auth_token) \(.ct0)"' $input |
      while read kind username auth_token ct0; do
        if [[ "$raw" -eq 1 ]]; then
            verify | jq
          else
            verify | pretty | xargs echo "${auth_token} ${kind}"
        fi
        sleep 2
      done
  elif [[ "$input" =~ ^[0-9a-f]{40}$ ]]; then
    auth_token="$input"
    ct0=$(openssl rand -hex 16) # ct0
    if [[ "$raw" -eq 1 ]]; then
        verify | jq
      else
        verify | pretty | xargs echo "${input}"
    fi
  else
    echo "usage: $0 [-r raw] [sessions.jsonl | 40 character auth_token]"
    exit 1
fi
