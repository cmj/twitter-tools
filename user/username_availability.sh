#!/bin/bash
# simple username availability check

# source auth_token, x_csrf_token
. ~/.env-twitter

username=$1

if [ -z $username ]; then echo "Usage: $0 username"; exit 1; fi


# main.js
#bearer_token="AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

# main.js alt
#bearer_token="AAAAAAAAAAAAAAAAAAAAAMupswEAAAAANC5Yk%2FHGiZmGDRV3EhXMBO3uX08%3DEwAT9YySxXZXGrYScXeoKUaeyqXQFeNVWUW4SaZUvtegCUVjIi"

# Twitter for Android
#bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'

# Twitter for iPhone
#bearer_token="AAAAAAAAAAAAAAAAAAAAAAj4AQAAAAAAPraK64zCZ9CSzdLesbE7LB%2Bw4uE%3DVJQREvQNCZJNiz3rHO7lOXlkVOQkzzdsgu6wWgcazdMUaGoUGm"

# Twitter for Mac
bearer_token="AAAAAAAAAAAAAAAAAAAAAIWCCAAAAAAA2C25AxqI%2BYCS7pdfJKRH8Xh19zA%3D8vpDZzPHaEJhd20MKVWp3UR38YoPpuTX7UD2cVYo3YNikubuxd"

# Twitter for iPad (bad)
#bearer_token="AAAAAAAAAAAAAAAAAAAAAGHtAgAAAAAA%2Bx7ILXNILCqkSGIzy6faIHZ9s3Q%3DQy97w6SIrzE7lQwPJEYQBsArEE2fC25caFwRBvAGi456G09vGR"

header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

out=$(curl -s "${header[@]}" 'https://x.com/i/api/graphql/1bMz-9lPrmIXrhFmXntTHw/GetUsernameAvailabilityAndSuggestions' \
  -H 'content-type: application/json' \
  -d '{"variables":{"include_suggestions":false,"session_token":"","username":"'"${username}"'"},"queryId":""}' | 
  jq -r .data.get_username_availability_and_suggestions.available
)

printf '%-15s %s\n' "${username}" "${out}"


