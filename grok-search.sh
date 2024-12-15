#!/bin/bash
# Twitter Grok AI search example
# requires auth_token

auth_token=''

####
x_csrf_token=00000000000000000000000000000000

if [[ -z "$x_csrf_token" || -z "$auth_token" ]]; then
  echo "requires x_csrf_token and auth_token"
  exit 1
fi

usage() { echo "$0 query"; exit 1; }
[ ! "$*" ] && usage
input="$@"
query=$(perl -MURI::Escape -wlne 'print uri_escape $_' <<< "${input}")

bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
URL='https://api.twitter.com/graphql/gkjsKepM6gl_HmFWoWKfgg/SearchTimeline'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: TwitterAndroid/10.21.1" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")
snowflake=$(rand=$(shuf -i 100-999 -n1); echo $(((($(date +%s) * 1000) -1288834974657) << 22)) | sed -E "s/[0-9]{3}$/$rand/")

# default: "returnSearchResults":true,"returnCitations":true ... "eagerTweets":false,"serverHistory":false
curl -s 'https://api.x.com/2/grok/add_response.json' "${header[@]}" \
  -d '{"responses":[{"message":"'"${query}"'","sender":1,"promptSource":"","fileAttachments":[]}],"systemPromptName":"","grokModelOptionId":"grok-2a","conversationId":"'"${snowflake}"'","returnSearchResults":false,"returnCitations":false,"promptMetadata":{"promptSource":"NATURAL","action":"INPUT"},"imageGenerationCount":4,"requestFeatures":{"eagerTweets":false,"serverHistory":false}}' | 
  jq -r '.result | select(.postIds == null) | .message | select(. != null)' |
  tr -d '\n' | sed 's/$/\n/;s/\*\*//g'
