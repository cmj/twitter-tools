#!/bin/bash
# returns unusable oauth_token
# Grab oauth token for use with Nitter (requires Twitter account). 
# results: {"oauth_token":"xxxxxxxxxx-xxxxxxxxx","oauth_token_secret":"xxxxxxxxxxxxxxxxxxxxx"}
# 

username="$1"
password="$2"

if [[ -z "$username" || -z "$password" ]]; then
  echo "$0 <username> <password>"
  exit 1
fi

# Twitter for Android
#consumerKey* = "3nVuSoBZnx6U4vzUxf5w"
#consumerSecret* = "Bcs59EFbbsdF6Sl9Ng71smgStWEGwXXKSjYvPVt7qys"
bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'

guest_token=$(curl -s -XPOST https://api.twitter.com/1.1/guest/activate.json -H "Authorization: Bearer ${bearer_token}" -d "grant_type=client_credentials" | jq -r '.guest_token')
base_url='https://api.twitter.com/1.1/onboarding/task.json'
headers=(
  -H "Authorization: Bearer ${bearer_token}"
  -H "Host: api.twitter.com"
  -H "Content-Type: application/json"
  -H "Accept: */*"
  -H "User-Agent: TwitterAndroid/10.21.0-release.0 (310210000-r-0) ONEPLUS+A3010/9"
  -H "X-Twitter-Active-User: yes"
  -H "X-Twitter-API-Version: 5"
  -H "X-Twitter-Client: TwitterAndroid"
  -H "X-Twitter-Client-Version: 10.21.0-release.0"
  -H "OS-Version: 28"
  -H "System-User-Agent: Dalvik/2.1.0 (Linux; Android 9; ONEPLUS A3010)"
  -H "X-Twitter-Client-DeviceID: "
  -H "X-Guest-Token: ${guest_token}"
)

# start flow
flow_1=$(curl -si -XPOST "${base_url}?flow_name=login&api_version=1&known_device_token=&sim_country_code=us" "${headers[@]}" \
  -d '{"flow_token": null, "input_flow_data": {"country_code": null, "flow_context": {"referrer_context":{"referral_details": "utm_source=google-play&utm_medium=organic", "referrer_url": ""}, "start_location": {"location": "deeplink"}}, "requested_variant": null, "target_user_id": 0}}')

# get 'att', now needed in headers, and 'flow_token' from flow_1
att=$(sed -En 's/^att: (.*)\r/\1/p' <<< "${flow_1}")
flow_token=$(sed -n '$p' <<< "${flow_1}" | jq -r .flow_token)

# username
token_2=$(curl -s -XPOST "${base_url}" -H "att: ${att}" "${headers[@]}" \
  -d '{"flow_token": "'"${flow_token}"'", "subtask_inputs": [{"enter_text": {"suggestion_id": null, "text": "'"${username}"'", "link": "next_link"}, "subtask_id": "LoginEnterUserIdentifier"}]}' | jq -r .flow_token)

# password flow and print oauth_token and secret
curl -s -XPOST "${base_url}" -H "att: ${att}" "${headers[@]}" \
  -d '{"flow_token": "'"${token_2}"'", "subtask_inputs": [{"enter_password": {"password": "'"${password}"'", "link": "next_link"}, "subtask_id": "LoginEnterPassword"}]}' |
  jq -c '.subtasks[0]|if(.open_account) then {oauth_token: .open_account.oauth_token, oauth_token_secret: .open_account.oauth_token_secret} else empty end'
