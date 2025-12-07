#!/bin/bash
# Grab Twitter session for use with Nitter

username="$1"
password="$2"
curl_="curl" # set curl, or curl-impersonate wrapper (curl_chrome100, curl_ff117, curl_chrome99_android, etc)
debug=0 # [0|1] print responses 
cookie="cookies.txt" # tempfile for cookie jar

### end

if [[ -z "$username" || -z "$password" ]]; then
  echo "$0 username password [wait for totp code prompt]"
  exit 1
fi

base_url='https://api.x.com/1.1/onboarding/task.json'
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'

header=(-H "Host: api.x.com" -H "Accept: */*" -H "Authorization: Bearer ${bearer_token}" -H "Content-Type:application/json" -H "Referer: https://x.com/" -H "Accept-Language: en-US" -H "X-Twitter-Client-Language: en-US" -c "${cookie}")

# if NOT using curl-impersonate, override default curl useragent
if [[ "$curl_" == "curl" ]]; then
  header+=(-H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")
fi

### Grab guest token
activate=$("${curl_}" -s -XPOST "${header[@]}" -c "${cookie}" "https://api.x.com/1.1/guest/activate.json")
guest_token=$(jq -r '.guest_token' <<< "${activate}")
[[ "$debug" -eq 1 ]] && echo -e "\e[0;32m#### activate\e[0m\n${activate}\n\e[0;32m#### guest_token\e[0m\n${guest_token}\n"
header+=(-b "${cookie}" -H "X-Guest-Token: ${guest_token}")

### start flow
flow_1=$("${curl_}" -s "${base_url}?flow_name=login" "${header[@]}" \
  -d '{"input_flow_data":{"flow_context":{"debug_overrides":{},"start_location":{"location":"manual_link"}}},"subtask_versions":{"action_list":2,"alert_dialog":1,"app_download_cta":1,"check_logged_in_account":2,"choice_selection":3,"contacts_live_sync_permission_prompt":0,"cta":7,"email_verification":2,"end_flow":1,"enter_date":1,"enter_email":2,"enter_password":5,"enter_phone":2,"enter_recaptcha":1,"enter_text":5,"enter_username":2,"generic_urt":3,"in_app_notification":1,"interest_picker":3,"js_instrumentation":1,"menu_dialog":1,"notifications_permission_prompt":2,"open_account":2,"open_home_timeline":1,"open_link":1,"phone_verification":4,"privacy_options":1,"security_key":3,"select_avatar":4,"select_banner":2,"settings_list":7,"show_code":1,"sign_up":2,"sign_up_review":4,"tweet_selection_urt":1,"update_users":1,"upload_media":1,"user_recommendations_list":4,"user_recommendations_urt":1,"wait_spinner":3,"web_modal":1}}')
flow_token=$(jq -r .flow_token <<< "${flow_1}")
[[ "$debug" -eq 1 ]] && echo -e "\e[0;32m#### flow start\e[0m\n${flow_1}\n\e[0;32m#### flow_token\e[0m\n${flow_token}\n"

### ui_metrics 
flow_2=$("${curl_}" -s "${base_url}" "${header[@]}" \
  -d '{"flow_token": "'"${flow_token}"'", "subtask_inputs": [{"subtask_id": "LoginJsInstrumentationSubtask", "js_instrumentation": {"response": "{\"rf\":{\"a4fc506d24bb4843c48a1966940c2796bf4fb7617a2d515ad3297b7df6b459b6\":121,\"bff66e16f1d7ea28c04653dc32479cf416a9c8b67c80cb8ad533b2a44fee82a3\":-1,\"ac4008077a7e6ca03210159dbe2134dea72a616f03832178314bb9931645e4f7\":-22,\"c3a8a81a9b2706c6fec42c771da65a9597c537b8e4d9b39e8e58de9fe31ff239\":-12},\"s\":\"ZHYaDA9iXRxOl2J3AZ9cc23iJx-Fg5E82KIBA_fgeZFugZGYzRtf8Bl3EUeeYgsK30gLFD2jTQx9fAMsnYCw0j8ahEy4Pb5siM5zD6n7YgOeWmFFaXoTwaGY4H0o-jQnZi5yWZRAnFi4lVuCVouNz_xd2BO2sobCO7QuyOsOxQn2CWx7bjD8vPAzT5BS1mICqUWyjZDjLnRZJU6cSQG5YFIHEPBa8Kj-v1JFgkdAfAMIdVvP7C80HWoOqYivQR7IBuOAI4xCeLQEdxlGeT-JYStlP9dcU5St7jI6ExyMeQnRicOcxXLXsan8i5Joautk2M8dAJFByzBaG4wtrPhQ3QAAAZEi-_t7\"}", "link": "next_link"}}]}')
token_2=$(jq -r .flow_token <<< "${flow_2}")
[[ "$debug" -eq 1 ]] && echo -e "\e[0;32m#### ui_metrics\e[0m\n${flow_2}\n\e[0;32m#### ui_metrics flow_token\e[0m\n${token_2}\n"

### username
flow_3=$("${curl_}" -s "${base_url}" -b "${cookie}" "${header[@]}" \
  -d '{"flow_token":"'"${token_2}"'","subtask_inputs":[{"subtask_id":"LoginEnterUserIdentifierSSO","settings_list":{"setting_responses":[{"key":"user_identifier","response_data":{"text_data":{"result":"'"${username}"'"}}}],"link":"next_link"}}]}' ) 
# check if denied for "suspicious activity"
denied_check=$(jq -r 'if(.subtasks[0].cta.primary_text) then "\(.subtasks[0].cta.primary_text.text)" else empty end' <<< "${flow_3}")
if [ "$denied_check" ]; then 
  echo -e "\e[31m$denied_check\e[0m"
  exit 1
fi
token_3=$(jq -r .flow_token <<< "${flow_3}")
[[ "$debug" -eq 1 ]] && echo -e "\e[0;32m#### username\e[0m\n${flow_3}\n\e[0;32m#### username flow_token\e[0m\n${token_3}\n"

### password
flow_4=$("${curl_}" -s "${base_url}" "${header[@]}" \
  -d '{"flow_token":"'"${token_3}"'","subtask_inputs":[{"enter_password":{"password":"'"${password}"'","link":"next_link"},"subtask_id":"LoginEnterPassword"}]}')
token_4=$(jq -r .flow_token <<< "${flow_4}")
csrf=$(sed -En 's/.*ct0\t(.*)/\1/p' "${cookie}")
[[ "$debug" -eq 1 ]] && echo -e "\e[0;32m#### password\e[0m\n${flow_3}\n\e[0;32m#### password flow_token\e[0m\n${token_3}\n\e[0;32m#### x-csrf-token\e[0m\n${csrf}\n"
check_2fa=$(jq -r .subtasks[0].subtask_id <<< "${flow_4}")

### 2FA
if [[ "${check_2fa}" != "LoginTwoFactorAuthChallenge" ]]; then
    "${curl_}" -s -o /dev/null "${base_url}" "${header[@]}" -H "X-Csrf-Token: ${csrf}" \
      -d '{"flow_token":"'"${token_4}"'","subtask_inputs":[{"subtask_id":"AccountDuplicationCheck","check_logged_in_account":{"link":"AccountDuplicationCheck_false"}}]}}'
  else
    if [[ -z "$totp_code" ]]; then
      echo "@${username} - Use your code generator app to generate a code and enter it below:"
      read totp_code
    fi
    "${curl_}" -s -o /dev/null "${base_url}" "${header[@]}" -H "X-Csrf-Token: ${csrf}" \
      -d '{"flow_token":"'"${token_4}"'","subtask_inputs":[{"subtask_id":"LoginTwoFactorAuthChallenge","enter_text":{"text":"'"${totp_code}"'","link":"next_link"}}]}'
fi

### final step - 2025-11-24 - not authorized
#"${curl_}" -s -o /dev/null "${base_url}" "${header[@]}" -H "X-Csrf-Token: ${csrf}" \
#  -d '{"flow_token":"'"${token_4}"'","subtask_inputs":[{"subtask_id":"AccountDuplicationCheck","check_logged_in_account":{"link":"AccountDuplicationCheck_false"}}]}}' 

### final step - only requested to retrieve full ct0
auth_token=$(awk '/auth_token/ {print $7}' "${cookie}")
ct0=$(awk '$6~/ct0/ {print $7}' "${cookie}")

"${curl_}" -s -o /dev/null "https://api.x.com/1.1/account/verify_credentials.json?include_email=true&skip_status=false&include_entities=true" \
  -H "Authorization: Bearer ${bearer_token}" \
  -H "User-Agent: TwitterAndroid/10.21.1" \
  -H "X-Csrf-Token: ${ct0}" \
  -b "${cookie}" -c "${cookie}" \
  -H "Cookie: auth_token=${auth_token}; ct0=${ct0}"

ct0=$(awk '$6~/ct0/ {print $7}' "${cookie}")
[[ "$debug" -eq 1 ]] && echo -e "\n\e[0;32m#### ct0/x-csrf-token\e[0m\n${ct0}\n"

user_id=$(sed -n 's/.*twid.*"u=\(.*\)"/\1/p' "${cookie}")

# Nitter sessions.jsonl
echo "{\"kind\":\"cookie\",\"username\":\"${username}\",\"id\":\"${user_id}\",\"auth_token\":\"${auth_token}\",\"ct0\":\"${ct0}\"}" | 
  tee session-${username}-$EPOCHSECONDS.jsonl # log output

# remove temporary cookie file
rm -r "${cookie}"

