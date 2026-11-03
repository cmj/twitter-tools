#!/bin/bash
# Twitter API verify_credentials/isLoggedIn check for single auth_token
# or for nitter sessions.jsonl file
#
# usage: session-verify.sh [-r] [-j] [-w out.jsonl] [sessions.jsonl | 40 character auth_token]
#   -r           raw verify_credentials json output
#   -j           jsonl output, one nitter session line per account that verified:
#                  {"kind":"cookie","username":..,"id":..,"auth_token":..,"ct0":..}
#   -w out.jsonl write the (modified) sessions to out.jsonl

pretty() {
  jq -r '
    def susp: (.suspended? == true) or ([.errors[]?.code?] | any(. == 64));
    ((.screen_name? // "")
     + (if susp then ""
        elif (((.errors | arrays) // []) | any(.message? != null)) then "invalid"
        else "" end)
     + " "
     + (if susp then "\u001b[31mSUSPENDED\u001b[0m"
        elif .suspended == false then "\u001b[35mvalid\u001b[0m"
        else "" end)
    ) | select(length > 0)
  '
}

verify() {
  bearer_token="AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
  url="https://api.twitter.com/1.1/account/verify_credentials.json"
  user_agent="TwitterAndroid/10.53.2-release.0 (310532000-r-0)"
  curl -sG -D "${hdr}" "${url}" \
    -H "Authorization: Bearer ${bearer_token}" \
    -H "User-Agent: ${user_agent}" \
    -H "X-Csrf-Token: ${ct0}" \
    -H "Cookie: ct0=${ct0}; auth_token=${auth_token}" \
    --data-urlencode "include_email=true" \
    --data-urlencode "skip_status=true" \
    --data-urlencode "include_entities=true"
}

account_status() {
  jq -r '
    if (.suspended? == true) or ([.errors[]?.code?] | any(. == 64)) then "suspended"
    elif .suspended? == false then "valid"
    else "invalid" end
  ' <<< "$1" 2>/dev/null || echo invalid
}

update_line() {
  case "$2" in
    suspended) jq -c '.suspended = "true"' <<< "$1" ;;
    valid)     jq -c 'del(.suspended)' <<< "$1" ;;
    *)         printf '%s\n' "$1" ;;
  esac
}

emit_jsonl() {
  local new_ct0
  new_ct0=$(grep -i '^set-cookie: *ct0=' "$hdr" | tail -1 | sed 's/^[^=]*=//; s/;.*//' | tr -d '\r')
  jq -c --arg token "$2" --arg ct0 "${new_ct0:-$3}" '
    select((.id_str? // "") != "" and (.screen_name? // "") != "")
    | {kind: "cookie", username: .screen_name, id: .id_str, auth_token: $token, ct0: $ct0}
      + (if .suspended == true then {suspended: "true"} else {} end)
  ' <<< "$1" 2>/dev/null
}

usage() {
  echo "usage: $0 [-r raw] [-j jsonl] [-w out.jsonl] [sessions.jsonl | 40 character auth_token]"
  exit 1
}

raw=0
jsonl=0
out=""
while getopts ":rjw:" opt; do
  case "$opt" in
    r) raw=1 ;;
    j) jsonl=1 ;;
    w) out=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

input=$1

hdr=$(mktemp) || exit 1
tmp=""
trap 'rm -f "$tmp" "$hdr"' EXIT

if [[ -f "$input" ]]; then
    if [[ -n "$out" ]]; then
      tmp=$(mktemp) || exit 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "${line//[[:space:]]/}" ]] && continue

      # '|' delimiter: tab/space would collapse empty fields (e.g. oauth sessions)
      IFS='|' read -r kind username auth_token ct0 \
        <<< "$(jq -r '[.kind // "", .username // "", .auth_token // "", .ct0 // ""] | join("|")' <<< "$line")"

      # only cookie sessions can be checked here (oauth sessions have no auth_token)
      if [[ -z "$auth_token" || -z "$ct0" ]]; then
        echo "skipping ${username:-<unknown>} (${kind:-oauth}): no auth_token/ct0" >&2
        [[ -n "$tmp" ]] && printf '%s\n' "$line" >> "$tmp"
        continue
      fi

      resp=$(verify)
      if [[ "$jsonl" -eq 1 ]]; then
          emit_jsonl "$resp" "$auth_token" "$ct0"
        elif [[ "$raw" -eq 1 ]]; then
          jq <<< "$resp"
        else
          pretty <<< "$resp" | xargs echo "${auth_token} ${kind}"
      fi

      [[ -n "$tmp" ]] && update_line "$line" "$(account_status "$resp")" >> "$tmp"
      sleep 2
    done < "$input"

    if [[ -n "$out" ]]; then
      # cat instead of mv: keeps the inode/permissions (docker file bind mounts)
      cat "$tmp" > "$out" && echo "wrote ${out}" >&2
    fi
  elif [[ "$input" =~ ^[0-9a-f]{40}$ ]]; then
    [[ -n "$out" ]] && echo "note: -w only applies to a sessions.jsonl file, ignoring" >&2
    auth_token="$input"
    ct0=$(openssl rand -hex 16) # ct0
    resp=$(verify)
    if [[ "$jsonl" -eq 1 ]]; then
        emit_jsonl "$resp" "$auth_token" "$ct0"
      elif [[ "$raw" -eq 1 ]]; then
        jq <<< "$resp"
      else
        pretty <<< "$resp" | xargs echo "${input}"
    fi
  else
    usage
fi
