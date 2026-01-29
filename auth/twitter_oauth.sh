#!/usr/bin/env bash
# Grab oauth token for use with Nitter 

username="$1"
password="$2"
totp_code="$3"

if [[ -z "$username" || -z "$password" ]]; then
  echo "$0 <username> <password> (totp_code or wait for prompt)"
  exit 1
fi

bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'

guest_token=$(curl -s -XPOST https://api.twitter.com/1.1/guest/activate.json \
  -H "Authorization: Bearer ${bearer_token}" \
  -H "User-Agent: TwitterAndroid/10.21.0-release.0 (310210000-r-0) ONEPLUS+A3010/9" \
  -d "grant_type=client_credentials" | jq -r '.guest_token')

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
att=$(col -b <<< "${flow_1}" | sed -En 's/^att: (.*)/\1/p')
headers+=(-H "att: ${att}")
flow_token=$(sed -n '$p' <<< "${flow_1}" | jq -r .flow_token)

# username
flow_2=$(curl -s -XPOST "${base_url}" "${headers[@]}" \
  -d '{"flow_token": "'"${flow_token}"'", "subtask_inputs": [{"enter_text": {"suggestion_id": null, "text": "'"${username}"'", "link": "next_link"}, "subtask_id": "LoginEnterUserIdentifier"}]}')

# check if denied for "suspicious activity"
denied_check=$(jq -r 'if(.subtasks[0].cta.primary_text) then "\(.subtasks[0].cta.primary_text.text)" else empty end' <<< "${flow_2}")
if [ "$denied_check" ]; then
  echo -e "\e[31m$denied_check\e[0m"
  exit 1
fi

token_2=$(jq -r .flow_token <<< "${flow_2}")

# password 
flow_3=$(curl -s -XPOST "${base_url}" "${headers[@]}" \
  -d '{"flow_token": "'"${token_2}"'", "subtask_inputs": [{"enter_password": {"password": "'"${password}"'", "link": "next_link"}, "subtask_id": "LoginEnterPassword"}]}')
token_3=$(jq -r .flow_token <<< "${flow_3}")
check_2fa=$(jq -r .subtasks[0].subtask_id <<< "${flow_3}")

# 2FA
if [[ "${check_2fa}" != "LoginTwoFactorAuthChallenge" ]]; then
    flow_end=$(curl -s "${base_url}" "${headers[@]}" \
      -d '{"flow_token":"'"${token_3}"'","subtask_inputs":[{"subtask_id":"AccountDuplicationCheck","check_logged_in_account":{"link":"AccountDuplicationCheck_false"}}]}}')
  else
    if [[ -z "$totp_code" ]]; then
      echo "@${username} - Use your code generator app to generate a code and enter it below:"
      read totp_code
    fi
    flow_end=$(curl -s "${base_url}" "${headers[@]}" \
      -d '{"flow_token":"'"${token_3}"'","subtask_inputs":[{"subtask_id":"LoginTwoFactorAuthChallenge","enter_text":{"text":"'"${totp_code}"'","link":"next_link"}}]}')
fi

# print oauth token and secret
jq -c '.subtasks[0]|if(.open_account) then {oauth_token: .open_account.oauth_token, oauth_token_secret: .open_account.oauth_token_secret} else empty end' <<< "${flow_end}"
