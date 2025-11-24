#!/bin/bash
# Twitter "About" page
# Very rate-limited: 50 requests per 15 minutes

# requires auth_token.
#auth_token=""
source ~/.env-twitter
screen_name=$1

file="${screen_name}-$EPOCHSECONDS" # save output

usage() { echo -e "Show Twitter account location (requires auth_token)\n $0 <screen_name>"; exit 1; }
[[ ! "$auth_token" || ! "$screen_name" ]] && usage

# generate random ct0
x_csrf_token=$(tr -dc 0-9a-f < /dev/urandom | head -c 32)

####
bearer_token='AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
header=(
  -H "Authorization: Bearer ${bearer_token}"
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" 
  -H "X-Csrf-Token: ${x_csrf_token}"
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}"
)

#        queryId
# old    4hPpWPld-iu2MDvfn1xoxQ no location
#        qZ92r6KDO0_GZxVJGM33XA
# latest XRqGa7EeokUU5kppkh13EA includes user id_str
queryId="XRqGa7EeokUU5kppkh13EA"
url="https://x.com/i/api/graphql/$queryId/AboutAccountQuery"
variables='{"screenName":"'"${screen_name}"'"}'


output=$(curl -sv -G "${header[@]}" "${url}" --data-urlencode "variables=${variables}" 2>&1)
head -n-1 <<< "${output}" | sed -n '/^[<>]/p' > "${file}-debug.out" # capture request/response headers
tail -1 <<< "${output}" |
  tee "${file}.json" |
  jq -r '.data.user_result_by_screen_name.result | "\(.core.screen_name) (\(.core.name)) | created: \(.core.created_at | strptime("%a %b %d %H:%M:%S +0000 %Y") | strftime("%Y-%m-%d %H:%M:%S UTC")) | ID: \(.rest_id) | Based in: \(.about_profile.account_based_in) | Connected via: \(.about_profile.source) | Accurate: \(.about_profile.location_accurate) | Username changes: \(.about_profile.username_changes.count)\(if(.about_profile.username_changes.last_changed_at_msec) then " (last change: \(.about_profile.username_changes.last_changed_at_msec[0:-3] | tonumber | strftime("%Y-%m-%d %H:%M:%S")))" else "" end)"'

