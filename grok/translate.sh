#!/bin/bash
# Translate a tweet using grok.
# usage: translate.sh <tweet id | tweet url> [dst_lang] (dst_lang defaults to "en")

auth_token=""
x_csrf_token=""

# source file for envars instead
. ~/.env-twitter

####
if [[ -z "$x_csrf_token" || -z "$auth_token" ]]; then
  echo "requires x_csrf_token and auth_token"
  exit 1
fi

usage() { echo "translate <tweet id or url> [dst_lang, default en]"; exit 0; }
[ ! "$1" ] && usage

id=$(grep -oE '[0-9]{2,}' <<< "$1" | tail -1)
dst_lang=${2:-en}

if [ -z "$id" ]; then
  echo "could not find a post id in: $1"
  exit 1
fi

bearer_token='AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
URL='https://api.x.com/2/grok/translation.json'
header=(
  -H "Authorization: Bearer ${bearer_token}"
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:159.0) Gecko/20100101 Firefox/159.0"
  -H "X-Csrf-Token: ${x_csrf_token}"
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}"
  -H "x-twitter-auth-type: OAuth2Session"
  -H "x-twitter-client-language: en"
  -H "x-twitter-active-user: yes"
  -H "Origin: https://x.com"
)

result=$(curl -s "$URL" "${header[@]}" \
  -H 'Content-Type: text/plain;charset=UTF-8' \
  --data-raw '{"content_type":"POST","id":"'"${id}"'","dst_lang":"'"${dst_lang}"'"}')

# uncomment for raw output
#echo "${result}" > /tmp/translate-$EPOCHSECONDS.out

text=$(jq -r '.result.text // empty' <<< "${result}" 2>/dev/null)

if [ -n "$text" ]; then
  printf '%s' "${text}" | tr -d '\n'
  echo
else
  echo "no translation returned:" >&2
  echo "${result}" >&2
  exit 1
fi
