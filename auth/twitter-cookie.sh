#!/bin/bash
# Grab auth_token, x-csrf-token for use with Nitter (cookies-branch) and other tools.
# Requires Twitter account.
# nitter.conf (https://github.com/cmj/nitter/tree/cookie_header)
# cookies.json (https://github.com/d60/twikit/issues/227)

username=""
password=""

# Two-Factor Authentication
# - Wait for prompt, use authentication app to get code.
# You can use any time-based one time password (TOTP) authentication app like Google Authenticator, Authy, Duo Mobile, 1Password, etc.)
# - OR enter here your one-time backup code (limit of 5 active codes, must be used in order created; out of order sequence revokes all codes)
totp_code=""

if [[ -z "$username" || -z "$password" ]]; then
  echo "needs username and password"
  exit 1
fi

cookie="cookies.txt"
#cookies_json="cookies-$username-$EPOCHSECONDS.json"
cookies_json="cookies.json"

###
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Host: api.twitter.com" -H "Accept: */*" -H "Authorization: Bearer ${bearer_token}" -H "Content-Type:application/json" -H "Referer: https://x.com/" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "Accept-Language: en-US" -H "X-Twitter-Client-Language: en-US")
guest_token=$(curl -s -XPOST "${header[@]}" -c "${cookie}" "https://api.twitter.com/1.1/guest/activate.json" | jq -r '.guest_token')

header2=("${header[@]}" -H "X-Guest-Token: ${guest_token}")
base_url='https://api.twitter.com/1.1/onboarding/task.json'
trans_id=$(tr -dc 0-9A-Za-z < /dev/urandom | head -c 94) # random string

# start flow
flow_token=$(curl -s -XPOST "${base_url}?flow_name=login" "${header2[@]}" -b "${cookie}" -c "${cookie}" \
  -d '{"input_flow_data":{"requested_variant":"'"${trans_id}"'","flow_context":{"debug_overrides":{},"start_location":{"location":"manual_link"}}},"subtask_versions":{"action_list":2,"alert_dialog":1,"app_download_cta":1,"check_logged_in_account":2,"choice_selection":3,"contacts_live_sync_permission_prompt":0,"cta":7,"email_verification":2,"end_flow":1,"enter_date":1,"enter_email":2,"enter_password":5,"enter_phone":2,"enter_recaptcha":1,"enter_text":5,"enter_username":2,"generic_urt":3,"in_app_notification":1,"interest_picker":3,"js_instrumentation":1,"menu_dialog":1,"notifications_permission_prompt":2,"open_account":2,"open_home_timeline":1,"open_link":1,"phone_verification":4,"privacy_options":1,"security_key":3,"select_avatar":4,"select_banner":2,"settings_list":7,"show_code":1,"sign_up":2,"sign_up_review":4,"tweet_selection_urt":1,"update_users":1,"upload_media":1,"user_recommendations_list":4,"user_recommendations_urt":1,"wait_spinner":3,"web_modal":1}}' | jq -r .flow_token)

# ui_metrics 
flow_2=$(curl -s -XPOST "${base_url}" "${header2[@]}" -b "${cookie}" -c "${cookie}" \
  -d '{"flow_token": "'"${flow_token}"'", "subtask_inputs": [{"subtask_id": "LoginJsInstrumentationSubtask", "js_instrumentation": {"response": "{\"rf\":{\"a4fc506d24bb4843c48a1966940c2796bf4fb7617a2d515ad3297b7df6b459b6\":121,\"bff66e16f1d7ea28c04653dc32479cf416a9c8b67c80cb8ad533b2a44fee82a3\":-1,\"ac4008077a7e6ca03210159dbe2134dea72a616f03832178314bb9931645e4f7\":-22,\"c3a8a81a9b2706c6fec42c771da65a9597c537b8e4d9b39e8e58de9fe31ff239\":-12},\"s\":\"ZHYaDA9iXRxOl2J3AZ9cc23iJx-Fg5E82KIBA_fgeZFugZGYzRtf8Bl3EUeeYgsK30gLFD2jTQx9fAMsnYCw0j8ahEy4Pb5siM5zD6n7YgOeWmFFaXoTwaGY4H0o-jQnZi5yWZRAnFi4lVuCVouNz_xd2BO2sobCO7QuyOsOxQn2CWx7bjD8vPAzT5BS1mICqUWyjZDjLnRZJU6cSQG5YFIHEPBa8Kj-v1JFgkdAfAMIdVvP7C80HWoOqYivQR7IBuOAI4xCeLQEdxlGeT-JYStlP9dcU5St7jI6ExyMeQnRicOcxXLXsan8i5Joautk2M8dAJFByzBaG4wtrPhQ3QAAAZEi-_t7\"}", "link": "next_link"}}]}' | jq -r .flow_token)

# username
flow_3=$(curl -s -XPOST "${base_url}" -b "${cookie}" "${header2[@]}" \
  -d '{"flow_token":"'"${flow_2}"'","subtask_inputs":[{"subtask_id":"LoginEnterUserIdentifierSSO","settings_list":{"setting_responses":[{"key":"user_identifier","response_data":{"text_data":{"result":"'"${username}"'"}}}],"link":"next_link"}}]}' ) 

# check if denied for "suspicious activity"
# can try a few times even if flagged
denied_check=$(jq -r 'if(.subtasks[0].cta.primary_text) then "\(.subtasks[0].cta.primary_text.text)" else empty end' <<< "${flow_3}")
if [ "$denied_check" ]; then echo -e "\e[31m$denied_check\e[0m"; exit; fi

token_3=$(jq -r .flow_token <<< "${flow_3}")

# password
flow_4=$(curl -s -XPOST "${base_url}" "${header2[@]}" -b "${cookie}" -c "${cookie}" \
  -d '{"flow_token":"'"${token_3}"'","subtask_inputs":[{"enter_password":{"password":"'"${password}"'","link":"next_link"},"subtask_id":"LoginEnterPassword"}]}')
csrf=$(sed -En 's/.*ct0\t(.*)/\1/p' "${cookie}")
token_4=$(jq -r .flow_token <<< "${flow_4}")
check_2fa=$(jq -r .subtasks[0].subtask_id <<< "${flow_4}")

# 2FA
if [[ "${check_2fa}" != "LoginTwoFactorAuthChallenge" ]]; then
    curl -s -o /dev/null -XPOST "${base_url}" -b "${cookie}" -c "${cookie}" "${header2[@]}" -H "X-Csrf-Token: ${csrf}" \
      -d '{"flow_token":"'"${token_4}"'","subtask_inputs":[{"subtask_id":"AccountDuplicationCheck","check_logged_in_account":{"link":"AccountDuplicationCheck_false"}}]}}'
  else
    if [[ -z "$totp_code" ]]; then
      echo "@${username} - Use your code generator app to generate a code and enter it below."
      read totp_code
    fi
    curl -s -o /dev/null -XPOST "${base_url}" -b "${cookie}" -c "${cookie}" "${header2[@]}" -H "X-Csrf-Token: ${csrf}" \
      -d '{"flow_token":"'"${token_4}"'","subtask_inputs":[{"subtask_id":"LoginTwoFactorAuthChallenge","enter_text":{"text":"'"${totp_code}"'","link":"next_link"}}]}'
fi

# final step
curl -s -o /dev/null -XPOST "${base_url}" -b "${cookie}" -c "${cookie}" "${header2[@]}" -H "X-Csrf-Token: ${csrf}" \
  -d '{"flow_token":"'"${flow_4}"'","subtask_inputs":[{"subtask_id":"AccountDuplicationCheck","check_logged_in_account":{"link":"AccountDuplicationCheck_false"}}]}}'

#############
auth_token=$(sed -En 's/.*auth_token\t(.*)/\1/p' "${cookie}")
ct0=$(sed -En 's/.*ct0\t(.*)/\1/p' "${cookie}")

# verbose output
echo "Cookie = \"ct0=${ct0}; auth_token=${auth_token}\""
#echo "x-csrf-token = ${ct0}"  
#echo "--- nitter.conf (https://github.com/cmj/nitter/tree/cookie_header) ---"
#echo "cookieHeader = \"ct0=${ct0}; auth_token=${auth_token}\""
#echo "xCsrfToken = \"${ct0}\""
#echo "--- cookies.json (https://github.com/d60/twikit/issues/227) ---"

# ugly way to convert netscape cookie to json, but works
# write to cookies.json
sed -En 's/"/\\"/g;s/.*twitter.*\t.*\t(.*)\t(.*)/"\1":"\2",/p' "${cookie}" | tr -d '\n' | sed 's/^/\{/;s/,$/\}/' | jq -c > "${cookies_json}"
echo "--- Cookies written to ${cookies_json}"

# remove temporary netscape cookie file
rm -r "${cookie}"
