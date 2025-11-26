#!/bin/bash
# Fetch multiple Twitter user info by ID

if [ -f .env ]; then
  . .env
    if [[ -z $auth_token || -z $x_csrf_token ]]; then
      echo "set auth_token and x_csrf_token in .env"; exit 1
    fi
  else
    echo "set credentials in .env"; exit 1
fi

####
bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

# nasa: 11348282 cnn: 759251 elonmusk: 44196397
api='https://x.com/i/api/graphql/lc85bOG5T3IIS4u485VtBg/UsersByRestIds'
variables='{"userIds":[11348282,759251,44196397]}'
features='{"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true}'

####
curl -s -G "${header[@]}" $api \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" |
  jq 

