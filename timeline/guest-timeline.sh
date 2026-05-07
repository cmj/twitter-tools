#!/usr/bin/env bash
# guest-timeline.sh — Fetch Twitter timeline as a guest
# Usage: guest-timeline.sh [OPTIONS] <screen_name>

set -euo pipefail

BEARER_TOKEN='AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
USER_AGENT='TwitterAndroid/10.21.1'

USER_URL='https://x.com/i/api/graphql/-oaLodhGbbnzJBACb1kk2Q/UserByScreenName'
USER_FEATURES='{"hidden_profile_likes_enabled":false,"hidden_profile_subscriptions_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"subscriptions_verification_info_is_identity_verified_enabled":false,"subscriptions_verification_info_verified_since_enabled":true,"highlights_tweets_tab_ui_enabled":true,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true}'

TWEETS_URL='https://api.x.com/graphql/oRJs8SLCRNRbQzuZG93_oA/UserTweets'
TWEETS_FEATURES='{"creator_subscriptions_tweet_preview_api_enabled":false,"communities_web_enable_tweet_community_results_fetch":false,"c9s_tweet_anatomy_moderator_badge_enabled":false,"articles_preview_enabled":false,"tweetypie_unmention_optimization_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"view_counts_everywhere_api_enabled":false,"longform_notetweets_consumption_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":false,"standardized_nudges_misinfo":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"tweet_with_visibility_results_prefer_gql_media_interstitial_enabled":false,"rweb_video_timestamps_enabled":false,"longform_notetweets_rich_text_read_enabled":false,"longform_notetweets_inline_media_enabled":false,"rweb_tipjar_consumption_enabled":false,"responsive_web_graphql_exclude_directive_enabled":false,"verified_phone_label_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_enhance_cards_enabled":false,"rweb_lists_timeline_redesign_enabled":false,"responsive_web_media_download_video_enabled":false}'

COUNT=20
SAVE=false
SORT_CHECK=false
OUTPUT_FILE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <screen_name>

Fetch timeline of a Twitter user without authentication.

Arguments:
  screen_name       Twitter/X username (with or without leading @)

Options:
  -n, --count N     Number of tweets to fetch (default: 20)
  -s, --save        Save output to a timestamped JSON file (<screen_name>-<epoch>.json)
  -o, --output FILE Save output to a specific file; use - for stdout (implies --save)
  -c, --sort-check  Print whether the timeline is sorted by likes or recency
                    Not 100% accurate - accounts seem to need over 100 tweeets?
  -h, --help        Show this help message and exit

Examples:
  $(basename "$0") NWS_NTWC
  $(basename "$0") --count 50 --save elonmusk
  $(basename "$0") -n 10 -c -o musk-tweets.json @elonmusk
EOF
  exit 0
}

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)       usage ;;
    -n|--count)      COUNT="$2"; shift 2 ;;
    -s|--save)       SAVE=true; shift ;;
    -o|--output)     OUTPUT_FILE="$2"; SAVE=true; shift 2 ;;
    -c|--sort-check) SORT_CHECK=true; shift ;;
    -*)              echo "Unknown option: $1" >&2; usage ;;
    *)               SCREEN_NAME="${1/@}"; shift ;;
  esac
done

if [[ -z "${SCREEN_NAME:-}" ]]; then
  echo "Error: screen_name is required." >&2
  usage
fi

get_guest_token() {
  curl -s -XPOST \
    -H "Authorization: Bearer ${BEARER_TOKEN}" \
    "https://api.twitter.com/1.1/guest/activate.json" \
    | jq -r '.guest_token'
}

lookup_user() {
  local screen_name="$1"
  local variables='{"screen_name":"'"${screen_name}"'"}'

  curl -sG "${USER_URL}" \
    "${HEADERS[@]}" \
    --data-urlencode "variables=${variables}" \
    --data-urlencode "features=${USER_FEATURES}"
}

fetch_tweets() {
  local user_id="$1"
  local count="$2"
  local variables='{"userId":"'"${user_id}"'","count":'"${count}"',"includePromotedContent":false,"withQuickPromoteEligibilityTweetFields":false,"withVoice":true,"withV2Timeline":true}'

  curl -sG "${TWEETS_URL}" \
    "${HEADERS[@]}" \
    --data-urlencode "variables=${variables}" \
    --data-urlencode "features=${TWEETS_FEATURES}"
}

check_sort_order() {
  local tweets_json="$1"
  jq -r '.data.user.result.timeline.timeline.instructions[1].entries[0].content.itemContent.tweet_results.result.core.user_results.result.core as $c |
    "@" + $c.screen_name + " (" + $c.name + ") " +
    if (.data.user.result.timeline.timeline.instructions[-2].entries[0].content.clientEventInfo.component?
        == "profile_best_highlights")
    then "[-] Sorted by \u001b[31mlikes\u001b[0m"
    else "[+] Sorted by \u001b[32mrecency\u001b[0m"
    end' <<< "${tweets_json}"
}

save_output() {
  local tweets_json="$1"
  local screen_name="$2"
  local outfile="${OUTPUT_FILE:-${screen_name}-${EPOCHSECONDS}.json}"

  if [[ "${outfile}" == "-" ]]; then
      jq . <<< "${tweets_json}"
    else
      jq . <<< "${tweets_json}" > "${outfile}"
      echo "Saved to: ${outfile}" >&2
  fi
}

GUEST_TOKEN=$(get_guest_token)

if [[ -z "$GUEST_TOKEN" || "$GUEST_TOKEN" == "null" ]]; then
  echo "Error: Failed to obtain guest token." >&2
  exit 1
fi

HEADERS=(
  -H "Authorization: Bearer ${BEARER_TOKEN}"
  -H "User-Agent: ${USER_AGENT}"
  -H "x-guest-token: ${GUEST_TOKEN}"
)

user_lookup=$(lookup_user "${SCREEN_NAME}")
user_id=$(jq -r '.data.user.result.rest_id' <<< "${user_lookup}")

if [[ "$user_id" == "null" || -z "$user_id" ]]; then
  echo "Error: Invalid or not found username: @${SCREEN_NAME}" >&2
  exit 1
fi

# canonical casing for continuity
SCREEN_NAME=$(jq -r '.data.user.result.core.screen_name' <<< "${user_lookup}")

user_tweets=$(fetch_tweets "${user_id}" "${COUNT}")

if $SORT_CHECK; then
  check_sort_order "${user_tweets}"
fi

if $SAVE; then
    save_output "${user_tweets}" "${SCREEN_NAME}"
  elif ! $SORT_CHECK; then
    jq . <<< "${user_tweets}"
fi
