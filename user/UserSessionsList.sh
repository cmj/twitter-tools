#!/bin/bash
# Retrieve session login info for an account

auth_token=$1

if [ -z $auth_token ]; then echo "Usage: $0 auth_token"; exit 1; fi

# use static csrf token 
x_csrf_token='00000000000000000000000000000000'

####
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: TwitterAndroid/10.21.1" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

api='https://x.com/i/api/graphql/vJ-XatpmQSG8bDch8-t9Jw/UserSessionsList'
features='{"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":false,"verified_phone_label_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true}'

####
curl -s -G "${header[@]}" $api \
  --data-urlencode "features=${features}" |
  jq 

