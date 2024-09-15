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
trans_id=$(tr -dc A-Za-z < /dev/urandom | head -c 94)
header2=(-H "x-client-transaction-id: ${trans_id}" -H "Host: api.x.com" -H "sec-ch-ua: \"Not;A=Brand\";v=\"24\", \"Chromium\";v=\"128\"" -H "x-twitter-client-language: en" -H "sec-ch-ua-mobile: ?0" -H "authorization: Bearer ${bearer_token2}" -H "user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)Chrome/127.0.0.0 Safari/537.36" -H "content-type: application/json" -H "x-guest-token: ${guest_token}" -H "x-twitter-active-user: yes" -H "sec-ch-ua-platform: \"Linux\"" -H "accept: */*" -H "origin: https://x.com" -H "sec-fetch-site:same-site" -H "sec-fetch-mode: cors" -H "sec-fetch-dest: empty" -H "referer: https://x.com/" -H "accept-language: en-US,en;q=0.9" -H "priority: u=1, i")

# start flow
flow_1=$(curl -si -XPOST "${base_url}?flow_name=login" "${header2[@]}")
cookie=$(sed -En 's/^set-cookie: (.*;) Max.*/\1/p' <<< "${flow_1}" | tr '\n' ' ') 
flow_token=$(sed -n '$p' <<< "${flow_1}" | jq -r .flow_token)

# js_inst
token_1=$(curl -s -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" \
  -d '{"flow_token":"'"${flow_token}"'","subtask_inputs":[{"subtask_id":"LoginJsInstrumentationSubtask","js_instrumentation":{"response":"{\"rf\":{\"af4ad0f041e2b2cdda00a76bf4bbb31bebff5c5b48b546da6cbd065846a97bb8\":-118,\"b17b4e3939116c9760232b218de621ac846593ea16b8b4313c018df0a4821b54\":-7,\"a97c7869c444ce1a1c87b9e23ba0be30667dfc4381b5b035e7b611e02999e259\":-62,\"a659a3a519254330fe4425831a047b9b18420d2dfd47f1007d26f0cf9e65f172\":-1},\"s\":\"Ca4H3c_fESd6vDs1jBJTtl0b6_ZCCZGQqTaejV7S_3qU1j0TgmGHa0BzWesFKtOY1X_tU4akzxosDzVkb0ebB4mOj0GmLo6ToFi4rVyYOQyOu8NvKVwhHskUZyBRDNQU8u89FPW_ccDb_yTkQuAVg3DSiniu3ziRGxA4NQkar7f6NHSs2c4IaQzDueloXJvWUXvoalVmSq4GCEp_laGTOxefX3ARaE0ameC7ITx8AuWWDS-GtIOHkwapLpfQ3H4Q8RbAuu12QHXMUsrMQMTdiXAFQ3zML05ynUw7Ni99RvAlR8Y53WIK9f2gVd4J7PtdOlz046tTRq9bh_C_Ljq7YQAAAZHz1q0N\"}","link":"next_link"}}]}' | jq -r .flow_token)

# username
token_2=$(curl -s -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" \
  -d "{\"flow_token\":\"${token_1}\",\"subtask_inputs\":[{\"subtask_id\":\"LoginEnterUserIdentifierSSO\",\"settings_list\":{\"setting_responses\":[{\"key\":\"user_identifier\",\"response_data\":{\"text_data\":{\"result\":\"${username}\"}}}],\"link\":\"next_link\"}}]}" | jq -r .flow_token) 

echo "user ${token_2}"

# password
flow_3=$(curl -si -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" \
  -d '{"flow_token":"'"${token_2}"'","subtask_inputs":[{"enter_password":{"password":"'"${password}"'","link":"next_link"},"subtask_id":"LoginEnterPassword"}]}') # | jq -r .flow_token)

token_3=$(grep flow_token <<< "${flow_3}" | jq -r .flow_token)
cookie=$(sed -En 's/^set-cookie: (.*;) Max.*/\1/p' <<< "${flow_3}" | tr '\n' ' ')
csrf=$(sed -E 's/.*ct0=(.*); .*/\1/' <<< "${cookie}" | cut -d\; -f1)
echo "pass: ${token_3}"
echo "cookie: $cookie"
echo "csrf: $csrf"
echo "----------"

# grap auth_token and full csrf ??
success=$(curl -si -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" -H "x-csrf-token: ${csrf}" \
  -d "{\"flow_token\":\"${token_3}\",\"subtask_inputs\":[]}")
token_4=$(grep flow_token <<< "${success}" | jq -r .flow_token)
cookie=$(sed -En 's/^set-cookie: (.*;) Max.*/\1/p' <<< "${success}" | tr '\n' ' ')
csrf=$(sed -E 's/.*ct0=(.*); .*/\1/' <<< "${cookie}")

#echo "success ${success}"
echo "cookie: $cookie"
echo "x-csrf-token: $csrf"
echo "----------"
#exit

# finally print oauth_token and secret
curl -s -XPOST "${base_url}" -H "Cookie: ${cookie}" "${header2[@]}" -H "x-csrf-token: ${csrf}" \
  -d '{"flow_token":"'"${token_4}"'","subtask_inputs":[{"subtask_id":"AccountDuplicationCheck","check_logged_in_account":{"link":"AccountDuplicationCheck_false"}}]}}' | jq
  
#  jq -c '.subtasks[0]|if(.open_account) then {oauth_token: .open_account.oauth_token, oauth_token_secret: .open_account.oauth_token_secret} else empty end'
