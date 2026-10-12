#!/bin/bash
# Translate a tweet or Community Note (birdwatch) using grok.
#
# usage: translate.sh [options] <tweet id | tweet url | birdwatch note url> [dst_lang]
#   dst_lang defaults to "en"
#
# A Community Note is translated when -note is given, or when the argument
# contains "birdwatch" (any domain, e.g. https://x.com/i/birdwatch/n/<id>).
# Anything else is treated as a normal post.
#
# options:
#   -note, --note     treat the id as a Community Note
#   -t, --tco         keep t.co links as returned (default: expand to real URLs)
#   -1, --oneline     collapse newlines into single spaces (default: keep them)
#   -d, --debug       dump the raw JSON response to /tmp/translate-<type>-<id>-<epoch>.out

auth_token=""
x_csrf_token=""

# source file for envars instead
[ -f ~/.env-twitter ] && source ~/.env-twitter

####
if [[ -z "$x_csrf_token" || -z "$auth_token" ]]; then
  echo "requires x_csrf_token and auth_token" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
translate.sh [-note] [-t] [-1] [-d] <tweet id | url | birdwatch url> [dst_lang, default en]
  -note, --note    translate a Community Note (also auto-detected from a birdwatch url)
  -t,    --tco     keep t.co links instead of expanding them
  -1,    --oneline collapse newlines to spaces
  -d,    --debug   save raw response to /tmp
EOF
  exit 0
}

note_mode=0
expand=1
oneline=0
debug=0
args=()
for a in "$@"; do
  case "$a" in
    -note|--note)     note_mode=1 ;;
    -t|--tco)         expand=0 ;;
    -1|--oneline)     oneline=1 ;;
    -d|--debug)       debug=1 ;;
    -h|--help)        usage ;;
    *)                args+=("$a") ;;
  esac
done

[ "${#args[@]}" -eq 0 ] && usage

target="${args[0]}"
dst_lang="${args[1]:-en}"

[[ "$target" == *birdwatch* ]] && note_mode=1

id=$(grep -oE '[0-9]{2,}' <<< "$target" | tail -1)
if [ -z "$id" ]; then
  echo "could not find a post id in: $target" >&2
  exit 1
fi

if [ "$note_mode" -eq 1 ]; then
  content_type="COMMUNITY_NOTE"
else
  content_type="POST"
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

response=$(curl -s "$URL" "${header[@]}" \
  -H 'Content-Type: text/plain;charset=UTF-8' \
  --data-raw '{"content_type":"'"${content_type}"'","id":"'"${id}"'","dst_lang":"'"${dst_lang}"'"}')

if [ "$debug" -eq 1 ]; then
  echo "${response}" > "/tmp/translate-${content_type,,}-${id}-$(date +%s).out"
fi

text=$(sed -E 's/^data: ?//' <<< "${response}" | jq -rs --argjson expand "$expand" '
  ([.[].result.text? // empty] | join("")) as $t
  | if $expand == 1 then
      reduce ([.[].result.rich_text_entities? // empty] | add // [])[] as $e ($t;
        if ($e.ref.url? and $e.ref.expandedUrl?)
        then split($e.ref.url) | join($e.ref.expandedUrl)
        else . end)
    else $t end
' 2>/dev/null)

if [ -z "$text" ]; then
  echo "no translation returned:" >&2
  echo "${response}" >&2
  exit 1
fi

if [ "$oneline" -eq 1 ]; then
  # newlines -> single space, squeeze repeats, trim ends
  printf '%s' "${text}" | tr '\n' ' ' | sed -E 's/ +/ /g; s/^ //; s/ $//'
  echo
else
  printf '%s\n' "${text}"
fi
