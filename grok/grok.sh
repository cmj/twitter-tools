#!/usr/bin/env bash
# Grok chat example
# - mdcat is optional for markdown

CONV_ID_FILE="/tmp/grok-sh-convId"
BEARER_TOKEN='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'
GROK_MODEL="grok-3"
ENV_FILE="${GROK_ENV_FILE:-$HOME/.env-twitter}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <query>
       $(basename "$0") reset

Chat with Grok

Options:
  -s, --short     Request a short answer (plain text, no markdown rendering)
  -e, --env FILE  Env file with auth_token (default: ~/.env-twitter)
  -h, --help      Show this help message

Commands:
  reset           Start a new conversation (clears conversation ID)

Examples:
  $(basename "$0") "What is the Higgs boson?"
  $(basename "$0") -s "tldr: rust vs go"
  $(basename "$0") --env ~/.env-work "explain RAG"
  $(basename "$0") reset

Notes:
  - auth_token is read from the env file or \$auth_token environment variable.
  - Conversation ID is stored in ${CONV_ID_FILE}.
  - Markdown output is rendered with mdcat if available; falls back to plain text.
EOF
  exit 0
}

short=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage ;;
    -s|--short)   short=true; shift ;;
    -e|--env)     ENV_FILE="$2"; shift 2 ;;
    --)           shift; break ;;
    -*)           echo "Unknown option: $1" >&2; usage ;;
    *)            break ;;
  esac
done

[[ $# -eq 0 ]] && usage

input="$*"

[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

if [[ -z "${auth_token:-}" ]]; then
  echo "Error: auth_token not set. Add it to ${ENV_FILE} or export it." >&2
  exit 1
fi

ct0=$(xxd -l 16 -p /dev/urandom)

header=(
  -H "Authorization: Bearer ${BEARER_TOKEN}"
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:146.0) Gecko/20100101 Firefox/146.0"
  -H "X-Csrf-Token: ${ct0}"
  -H "Cookie: ct0=${ct0}; auth_token=${auth_token}"
  -H "Content-Type: application/json"
)

conversation_new() {
  local query_id="vvC5uy7pWWHXS2aDi1FZeA"
  local conv_id
  conv_id=$(
    curl -sf "${header[@]}" \
      "https://x.com/i/api/graphql/${query_id}/CreateGrokConversation" \
      -d '{"variables":{},"queryId":"'"${query_id}"'"}' |
    jq -r '.data.create_grok_conversation.conversation_id'
  )
  if [[ -z "$conv_id" || "$conv_id" == "null" ]]; then
    echo "Error: failed to create conversation. Check your auth_token." >&2
    exit 1
  fi
  echo "$conv_id" > "$CONV_ID_FILE"
  echo "$conv_id"
}

get_conversation_id() {
  if [[ -s "$CONV_ID_FILE" ]]; then
    cat "$CONV_ID_FILE"
  else
    conversation_new
  fi
}

clean_message() {
  perl -0pe 's|<grok:[^>]*>.*?</grok:[^>]*>||gs; s|</?grok:[^>]*>||g'
}

strip_markdown() {
  perl -0pe '
    s/\*{1,3}([^*]+)\*{1,3}/$1/g;
    s/_{1,2}([^_]+)_{1,2}/$1/g;
    s/`{1,3}[^`]*`{1,3}//g;
    s/^#{1,6}\s+//gm;
    s/!?\[([^\]]*)\]\([^)]*\)/$1/g;
    s/^\s*[-*+]\s+/  /gm;
    s/^\s*\d+\.\s+/  /gm;
    s/^>{1,}\s?//gm;
    s/^[-*_]{3,}\s*$//gm;
  '
}

print_output() {
  local text="$1"
  if $short; then
    echo "$text" | clean_message | strip_markdown | sed 's/Short answer: //'
  elif command -v mdcat &>/dev/null; then
    echo "$text" | clean_message | mdcat
  else
    echo "$text" | clean_message
  fi
}

# keep track of conversationId for threaded chats
if [[ "$input" == "reset" ]]; then
  conv_id=$(conversation_new)
  echo "Conversation reset. New ID: ${conv_id}"
  exit 0
fi

query="$input"
$short && query="short answer only. ${input}"
query=$(sed 's/"/\\"/g' <<< "$query")

conversationId=$(get_conversation_id)

result=$(curl -sf 'https://grok.x.com/2/grok/add_response.json' "${header[@]}" \
  -d '{
    "responses": [{"message":"'"${query}"'","sender":1,"promptSource":"","fileAttachments":[]}],
    "systemPromptName": "",
    "grokModelOptionId": "'"${GROK_MODEL}"'",
    "conversationId": "'"${conversationId}"'",
    "returnSearchResults": false,
    "returnCitations": false,
    "promptMetadata": {"promptSource":"NATURAL","action":"INPUT"},
    "imageGenerationCount": 4,
    "requestFeatures": {"eagerTweets":false,"serverHistory":false}
  }')

if [[ -z "$result" ]]; then
  echo "Error: empty response from API. Check your auth_token or try: $(basename "$0") reset" >&2
  exit 1
fi

message=$(
  jq -rs '
    [ .[]
      | .result
      | select(.postIds == null)
      | select(.messageTag == "final" or (.isThinking == false and .cardAttachment == null))
      | select(.message != null)
      | .message
    ] | join("")
  ' <<< "$result"
)

if [[ -z "$message" || "$message" == "null" ]]; then
  echo "Error: no message in response. Try: $(basename "$0") reset" >&2
  exit 1
fi

# images were disabled on free tier ~2026-01-09
images=$(jq -r '.result.imageAttachment | select(. != null) | "\(.imageUrl) \(.fileName)"' \
  <<< "$result" 2>/dev/null || true)

if [[ -n "$images" ]]; then
  echo "$images" | head -4 | while read -r url file; do
    curl -sf -o "/tmp/${file}" "$url" "${header[@]}"
    echo "[image saved: /tmp/${file}]"
  done
  print_output "$message"
else
  print_output "$message"
fi
