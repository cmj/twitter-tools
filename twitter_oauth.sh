#!/bin/bash
# Grab oauth token for use with Nitter (requires Twitter account). 
# results: {"oauth_token":"xxxxxxxxxx-xxxxxxxxx","oauth_token_secret":"xxxxxxxxxxxxxxxxxxxxx"}
# XXX errors out: "{"errors":[{"code":366,"message":"flow name LoginFlow is currently notaccessible"}]}"

username=""
password=""

if [[ -z "$username" || -z "$password" ]]; then
  echo "needs username and password"
  exit 1
fi

#bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'
bearer_token2='AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
guest_token=$(curl -s -XPOST https://api.x.com/1.1/guest/activate.json -H "Authorization: Bearer ${bearer_token2}" | jq -r '.guest_token')
base_url='https://api.x.com/1.1/onboarding/task.json'

# More info: https://antibot.blog/twitter-header-part-3/#testing
# They said x-client-transaction-id is useless at the time of writing?
trans_id=$(tr -dc 0-9A-Za-z < /dev/urandom | head -c 94) # random string

header2=(-H "x-client-transaction-id: ${trans_id}" -H "Host: api.x.com" -H "sec-ch-ua: \"Not;A=Brand\";v=\"24\", \"Chromium\";v=\"128\"" -H "x-twitter-client-language: en" -H "sec-ch-ua-mobile: ?0" -H "authorization: Bearer ${bearer_token2}" -H "user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36" -H "content-type: application/json" -H "x-guest-token: ${guest_token}" -H "x-twitter-active-user: yes" -H "sec-ch-ua-platform: \"Linux\"" -H "accept: */*" -H "origin: https://x.com" -H "sec-fetch-site:same-site" -H "sec-fetch-mode: cors" -H "sec-fetch-dest: empty" -H "referer: https://x.com/" -H "accept-language: en-US,en;q=0.9" -H "priority: u=1, i")

# start flow
flow_1=$(curl -si -XPOST "${base_url}?flow_name=login" "${header2[@]}")
cookie=$(sed -En 's/^set-cookie: (.*;) Max.*/\1/p' <<< "${flow_1}" | tr '\n' ' ') 
flow_token=$(sed -n '$p' <<< "${flow_1}" | jq -r .flow_token)

# ui_metrics 
# quickly added and is a complete mess
# https://gist.github.com/cmj/250fbd81075592063dfd686ebc073c6f
metrics_url=$(curl -s 'https://x.com/i/js_inst?c_name=ui_metrics')
lines=$(tr ';' '\n' <<< "${metrics}")
rks=$(sed -n '3,6p' <<< "${lines}" | sed -E "s/.*var (.*)=(.*)/\"\1\":\2,/" | tr -d '\n' | sed 's/,$//')
s=$(sed -En "s/^return \{.*(,'s':.*)/\1/p" <<< "${lines}" | sed "s/'/\"/g")
metrics=$(printf "{\"rf\": {$rks}$s" | sed 's/"/\\"/g')

token_1=$(curl -s -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" \
  -d '{"flow_token":"'"${flow_token}"'","subtask_inputs":[{"subtask_id":"LoginJsInstrumentationSubtask","js_instrumentation":{"response":"'"${metrics}"'","link":"next_link"}}]}' | jq -r .flow_token)

echo "metrics_flow: ${token_1}"

# username
flow_2=$(curl -s -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" \
  -d "{\"flow_token\":\"${token_1}\",\"subtask_inputs\":[{\"subtask_id\":\"LoginEnterUserIdentifierSSO\",\"settings_list\":{\"setting_responses\":[{\"key\":\"user_identifier\",\"response_data\":{\"text_data\":{\"result\":\"${username}\"}}}],\"link\":\"next_link\"}}]}") 

# check if denied for "suspicious activity"
flow_2_check=$(jq -r '.subtasks[0].cta.secondary_text.text' <<< "${flow_2}")
echo "denied_check: ${flow_2_check}"

token_2=$(jq -r .flow_token <<< "${flow_2}")
echo "user_flow: ${token_2}"

# password
flow_3=$(curl -si -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" \
  -d '{"flow_token":"'"${token_2}"'","subtask_inputs":[{"enter_password":{"password":"'"${password}"'","link":"next_link"},"subtask_id":"LoginEnterPassword"}]}') # | jq -r .flow_token)

#echo "${flow_3}"
#exit

token_3=$(grep flow_token <<< "${flow_3}" | jq -r .flow_token)
cookie=$(sed -En 's/^set-cookie: (.*;) Max.*/\1/p' <<< "${flow_3}" | tr '\n' ' ')
csrf=$(sed -E 's/.*ct0=(.*); .*/\1/' <<< "${cookie}" | cut -d\; -f1)
echo "pass_flow: ${token_3}"
echo "cookie: $cookie"
echo "csrf: $csrf"
echo "----------"

# grab auth_token and full csrf ??
# may not need this extra step
# both previous and this flow_token/csrf have been tried
success=$(curl -si -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" -H "x-csrf-token: ${csrf}" \
  -d "{\"flow_token\":\"${token_3}\",\"subtask_inputs\":[]}")
token_4=$(grep flow_token <<< "${success}" | jq -r .flow_token)
cookie=$(sed -En 's/^set-cookie: (.*;) Max.*/\1/p' <<< "${success}" | tr '\n' ' ')
csrf=$(sed -E 's/;[ ]?/\n/g' <<< "${cookie}" | sed -nr 's/ct0=(.*)/\1/p')
echo "cookie: $cookie"
echo "x-csrf-token: $csrf"
echo "----------"

# finally print oauth_token and secret
curl -s -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" -H "x-csrf-token: $csrf" \
  -d '{"flow_token":"'"${token_4}"'","subtask_inputs":[{"subtask_id":"AccountDuplicationCheck","check_logged_in_account":{"link":"AccountDuplicationCheck_false"}}]}}' | jq
  
#  jq -c '.subtasks[0]|if(.open_account) then {oauth_token: .open_account.oauth_token, oauth_token_secret: .open_account.oauth_token_secret} else empty end'
