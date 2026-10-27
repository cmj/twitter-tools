#!/bin/bash
# usage: t [-a] [-g] [-R] [-r] [tweet_id | url | @user [n]]
# guest (default): guest token, no login, no birdwatch info.
# -a: your session cookies from ~/.env-twitter (x_csrf_token, auth_token).

[ -f ~/.env-twitter ] && source ~/.env-twitter

usage() {
  cat << eof
usage: ${0##*/} [option] [tweet_id | url | @user [n]]
  @user [n]  the n-th tweet (default 1 = newest) in a user's timeline
             (pinned and retweets skipped; ~5 in guest mode, up to 20 with -a)
  default: guest token, no login (@user = originals only)
  option: -a[uth]  session cookies; @user = tweets and replies
          -R       guest @user: replies timeline instead of originals
          -a -s    print only the client label (iPhone, Web App, ...) of a tweet id
          -r[aw]   raw json dump
          -h[elp]  this help
  T_DEBUG=1  print guest-token activation and each request's http code/body to stderr
  env (~/.env-twitter): T_USER_QID T_ORIGINALS_QID T_REPLIES_QID T_TWEETS_REPLIES_QID
                        override the GraphQL query ids when X rotates them
eof
}

guest=1 raw=0 replies=0 srcmode=0
while [ $# -gt 0 ]; do
  case "$1" in
    -g|-guest|--guest)     guest=1; shift ;;
    -a|-auth|--auth)       guest=0; shift ;;
    -r|-raw|--raw)         raw=1; shift ;;
    -R|-replies|--replies) replies=1; shift ;;
    -s|-source|--source)   srcmode=1; shift ;;
    -h|-help|--help)       usage; exit 0 ;;
    *) break ;;
  esac
done

input="${1%#*}"
input="${input%%\?*}"
nth="${2:-1}"

user=""
case "$input" in
  @*)           user="${input#@}" ;;
  */status/*)   ;;
  *://*)        user="${input#*://*/}"; user="${user%%/*}" ;;
  ''|*[!0-9]*)  user="$input" ;;
esac
id="${input##*/}"
[ -n "$user" ] && id="$user"

case "$nth" in
  ''|*[!0-9]*|0) echo "${0##*/}: n must be a positive number, got '$nth'" >&2; exit 1 ;;
esac
[ -z "$id" ] && { usage; exit 1; }

ua="Mozilla/5.0 (X11; Linux x86_64; rv:148.0) Gecko/20100101 Firefox/148.0"
bearer_token="AAAAAAAAAAAAAAAAAAAAAPnA9gAAAAAAZHpqKYoDdMCaqTUBktzAdK38BGk%3DLNsI9r2BHSjZ7cl5wD6Sh6NhxwZd2j8lXDSd6GDoQVYBlzx5Ff"
bearer_auth="AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
bearers=("$bearer_token")
header=(-H "Authorization: Bearer ${bearer_auth}" -H "User-Agent: ${ua}" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

gql_host=https://x.com/i/api/graphql
q_user=${T_USER_QID:--oaLodhGbbnzJBACb1kk2Q}/UserByScreenName
q_orig=${T_ORIGINALS_QID:-jcbfqPu_2XMNOwVyGypRhw}/UserOriginalsTimeline
q_repl=${T_REPLIES_QID:-xz348nziCm96wndJ1S0MUQ}/UserRepliesTimeline
q_tar=${T_TWEETS_REPLIES_QID:--gxtzCQbBPmOwxnY-SbiHQ}/UserTweetsAndReplies
q_tweet_guest=(GZsN2Pc4knAoit6pXa4HSA/TweetResultByRestId WvlrBJ2bz8AuwoszWyie8A/TweetResultByRestId)
api='https://x.com/i/api/graphql/GZsN2Pc4knAoit6pXa4HSA/TweetResultByRestId'
cache=${XDG_CACHE_HOME:-$HOME/.cache}/t
mkdir -p "$cache"

variables='{"count":1,"withSafetyModeUserFields":true,"includePromotedContent":true,"withQuickPromoteEligibilityTweetFields":true,"withVoice":true,"withV2Timeline":true,"withDownvotePerspective":false,"withBirdwatchNotes":true,"withCommunity":true,"withSuperFollowsUserFields":true,"withReactionsMetadata":false,"withReactionsPerspective":false,"withSuperFollowsTweetFields":true,"isMetatagsQuery":false,"withReplays":true,"withClientEventToken":false,"withAttachments":true,"withConversationQueryHighlights":true,"withMessageQueryHighlights":true,"withMessages":true,"tweetId":"'"${id}"'"}'
features='{"creator_subscriptions_tweet_preview_api_enabled":true,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"tweetypie_unmention_optimization_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"tweet_with_visibility_results_prefer_gql_media_interstitial_enabled":true,"rweb_video_timestamps_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_enhance_cards_enabled":false}'
fieldToggles='{"withArticleRichContentState":true,"withArticlePlainText":true}'
features_tl='{"rweb_video_screen_enabled":false,"rweb_cashtags_enabled":true,"profile_label_improvements_pcf_label_in_post_enabled":true,"responsive_web_profile_redirect_enabled":false,"rweb_tipjar_consumption_enabled":false,"verified_phone_label_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"premium_content_api_read_enabled":false,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"c9s_list_members_action_api_enabled":false,"c9s_superc9s_indication_enabled":false,"responsive_web_grok_analyze_button_fetch_trends_enabled":false,"responsive_web_grok_analyze_post_followups_enabled":true,"rweb_cashtags_composer_attachment_enabled":true,"responsive_web_jetfuel_frame":true,"responsive_web_grok_share_attachment_enabled":true,"responsive_web_grok_annotations_enabled":true,"articles_preview_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"rweb_conversational_replies_downvote_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"content_disclosure_indicator_enabled":true,"content_disclosure_ai_generated_indicator_enabled":true,"responsive_web_grok_show_grok_translated_post":true,"responsive_web_grok_analysis_button_from_backend":true,"post_ctas_fetch_enabled":true,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":false,"responsive_web_grok_image_annotation_enabled":true,"responsive_web_grok_imagine_annotation_enabled":true,"responsive_web_grok_community_note_auto_translation_is_enabled":true,"responsive_web_enhance_cards_enabled":false}'

guest_token() {
  local gf=$cache/guest_token.${1: -8} gt h
  [ "$2" = new ] && rm -f "$gf"
  if [ -z "$(find "$gf" -mmin -120 -size +0 2>/dev/null)" ]; then
    for h in api.twitter.com api.x.com; do
      gt=$(curl -s -X POST -H "Authorization: Bearer $1" "https://$h/1.1/guest/activate.json" | jq -r '.guest_token // empty' 2>/dev/null)
      [ -n "$T_DEBUG" ] && echo "t: guest/activate via $h -> $([ -n "$gt" ] && echo "ok ...${gt: -4}" || echo FAILED)" >&2
      [ -n "$gt" ] && { printf '%s' "$gt" > "$gf"; break; }
    done
  fi
  cat "$gf" 2>/dev/null
}

gql() {
  local f=$features_tl u=$1 op=${1##*/} out code miss b gt gh try=0 renew= bi
  case $u in http*) ;; *) u=$gql_host/$u ;; esac
  bi=$(cat "$cache/bearer.$op" 2>/dev/null); bi=${bi:-0}
  ((bi < ${#bearers[@]})) || bi=0
  while :; do
    if ((guest)); then
      b=${bearers[bi]} gt=$(guest_token "$b" $renew)
      gh=(-H "Authorization: Bearer $b" -H "User-Agent: ${ua}" -H "x-guest-token: ${gt}")
    else
      gh=("${header[@]}")
    fi
    out=$(curl -s -G -w '\n%{http_code}' "${gh[@]}" "$u" --data-urlencode "variables=$2" \
      --data-urlencode "features=$f" --data-urlencode "fieldToggles=${3:-$fieldToggles}")
    code=${out##*$'\n'} out=${out%$'\n'*}
    printf '%s\n%s' "$code" "$out" > "$cache/last"
    [ -n "$T_DEBUG" ] && printf 't: %s http=%s bearer=...%s guest=...%s body=%.200s\n' "$op" "$code" "${b: -4}" "${gt: -4}" "$out" >&2
    renew=
    if ((guest)); then
      case $code in 401|403|404) if ((bi + 1 < ${#bearers[@]})); then ((bi++)); continue; fi ;; esac
      case $out in *'Bad guest token'*|*'"code":239'*|'') renew=new ;; esac
    fi
    ((try++ >= 2)) && break
    [ -n "$renew" ] && continue
    miss=$(jq -r '[(.errors // [])[].message | select(test("features cannot be null")) | sub("^.*cannot be null: "; "") | split(", ")[]] | unique | .[]' <<< "$out" 2>/dev/null)
    [ -n "$miss" ] || break
    f=$(jq -c --arg m "$miss" '. + ([$m | split("\n")[] | select(. != "")] | map({(.): true}) | add)' <<< "$f")
  done
  ((guest)) && [ "$code" = 200 ] && printf '%s' "$bi" > "$cache/bearer.$op"
  printf '%s' "$out"
}

apierr() {
  local m; m=$(sed 1d "$cache/last" | jq -r '(.errors // [])[0].message // empty' 2>/dev/null)
  printf 'http %s%s' "$(head -n1 "$cache/last")" "${m:+: $m}"
}

die() { echo "${0##*/}: $1 [$(apierr)]" >&2; exit 1; }

if ((srcmode)); then
  ((guest)) && { echo "${0##*/}: -s needs -a, the client label is only served to a logged-in session" >&2; exit 1; }
  out=$(curl -s -m 8 -w '\n%{http_code}' \
    -H "Authorization: Bearer ${bearer_auth}" -H "User-Agent: ${ua}" -H "X-Csrf-Token: ${x_csrf_token}" \
    -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}" \
    "https://x.com/i/api/2/timeline/conversation/${id}.json?count=1&include_reply_count=true&cards_platform=Web-13&include_entities=1&include_user_entities=1&include_cards=1&send_error_codes=1&tweet_mode=extended&include_ext_alt_text=true")
  code=${out##*$'\n'}
  [ "$code" = 200 ] || { echo "${0##*/}: source request refused (http $code)" >&2; exit 1; }
  printf '%s' "${out%$'\n'*}" | jq -r --arg id "$id" '(.globalObjects.tweets[$id].source // ([.globalObjects.tweets[]?.source] | first) // "")
    | gsub("<[^>]*>"; "") | sub("^Twitter (for )?"; "")' 2>/dev/null
  exit 0
fi

if [ -n "$user" ]; then
  lc=$(printf '%s' "$user" | tr 'A-Z' 'a-z')
  uid=$(cat "$cache/uid.$lc" 2>/dev/null)
  if [ -z "$uid" ]; then
    uid=$(gql "$q_user" "{\"screen_name\":\"${user}\",\"withSafetyModeUserFields\":true}" '{"withAuxiliaryUserLabels":false}' \
      | jq -r '.data.user.result.rest_id // empty' 2>/dev/null)
    [ -n "$uid" ] || die "couldn't resolve @${user} (not found, or stale query id: set T_USER_QID)"
    printf '%s' "$uid" > "$cache/uid.$lc"
  fi
  if ((! guest)); then tl=$q_tar; elif ((replies)); then tl=$q_repl; else tl=$q_orig; fi
  json=$(gql "$tl" "{\"userId\":\"${uid}\",\"count\":20,\"includePromotedContent\":false,\"withBirdwatchNotes\":true,\"withVoice\":true,\"withCommunity\":false,\"withDownvotePerspective\":true,\"withReactionsMetadata\":true,\"withReactionsPerspective\":true,\"includeHasBirdwatchNotes\":true,\"withV2Timeline\":true}" \
      '{"withArticleRichContentState":true,"withArticlePlainText":false}' |
    jq -c --argjson n "$nth" --arg uid "$uid" '
      [ .data.user.result | (.timeline_v2 // .timeline).timeline.instructions[]?
        | select((.type // .__typename) == "TimelineAddEntries") | .entries[]?
        | .content | (.itemContent?, (.items[]?.item.itemContent?))
        | select(. != null) | .tweet_results.result? | select(. != null)
        | (if .tweet then .tweet else . end)
        | select(.core.user_results.result.rest_id == $uid)
        | select(.legacy.retweeted_status_result == null) ] as $t
      | if ($t | length) < $n then {short: ($t | length)}
        else {data: {tweetResult: {result: $t[$n - 1]}}} end' 2>/dev/null)
  short=$(printf '%s' "$json" | jq -r '.short // empty' 2>/dev/null)
  [ -n "$short" ] && { echo "${0##*/}: only $short tweet(s) in @${user}'s timeline (asked for #$nth)" >&2; exit 1; }
  { [ -z "$json" ] || [ "$json" = null ]; } && die "no timeline data (stale query id? set T_ORIGINALS_QID / T_REPLIES_QID / T_TWEETS_REPLIES_QID)"
else
  if ((guest)); then
    for q in "${q_tweet_guest[@]}"; do
      json=$(gql "$q" "$variables")
      [ -n "$(printf '%s' "$json" | jq -r '.data.tweetResult.result // empty' 2>/dev/null)" ] && break
    done
  else
    json=$(gql "$api" "$variables")
  fi
  [ -n "$(printf '%s' "$json" | jq -r '.data.tweetResult.result // empty' 2>/dev/null)" ] || die "no tweet data (unavailable, or stale TweetResultByRestId id)"
fi

if [ "$raw" -eq 1 ]; then
  printf '%s\n' "$json" | jq . 2>/dev/null || printf '%s\n' "$json"
  exit 0
fi

jq_prog=$(cat <<'JQ'
def commas: tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",");
def color($c): "\u001b[\($c)m✓\u001b[0m";
def str: if type == "string" then . else "" end;

# full-size URL for a media entity: photo -> image url, video/gif -> best mp4
def mediaurl:
  if (.type == "video" or .type == "animated_gif") then
    ([(.video_info.variants // [])[] | select(.content_type == "video/mp4")] | max_by(.bitrate // 0) | .url)
      // .expanded_url // .media_url_https
  else (.media_url_https // .expanded_url) end;

# swap every t.co link in a text for its expanded url / full media url(s);
# t.co links that map to nothing are dropped
def expand($urls; $media):
  reduce ($urls // [])[] as $e (.;
    if ($e.url // "") != "" and ($e.expanded_url // "") != ""
    then split($e.url) | join($e.expanded_url) else . end)
  | ([($media // [])[] | mediaurl | select(. != null)]
     | reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end)) as $mu
  | ($mu | join(" ")) as $j
  | ([($media // [])[] | (.url // empty) | select(. != "")] | first // null) as $mt
  | (if ($mu | length) == 0 then .
     elif $mt != null and contains($mt) then split($mt) | join($j)
     elif test("https://t\\.co/[A-Za-z0-9]+") then sub("https://t\\.co/[A-Za-z0-9]+"; $j)
     else . + " " + $j end)
  | gsub("\\s*https://t\\.co/[A-Za-z0-9]+"; "")
  | sub("\\s+$"; "");

# GraphQL tweet (legacy-shaped; user fields from either the legacy or the newer core block) -> common record
def norm:
  (if .tweet then .tweet else . end)
  | .core.user_results.result as $u
  | if $u == null then null else
    { sn: ($u.legacy.screen_name // $u.core.screen_name), name: ($u.legacy.name // $u.core.name),
      vtype: ($u.legacy.verified_type // $u.verification.verified_type // ""),
      blue: (($u.is_blue_verified // $u.verification.is_blue_verified) == true),
      text: (.note_tweet.note_tweet_results.result.text // .legacy.full_text),
      urls: (.note_tweet.note_tweet_results.result.entity_set.urls // .legacy.entities.urls),
      media: (.legacy.extended_entities.media // .legacy.entities.media),
      limited: .legacy.limited_actions,
      replies: .legacy.reply_count, rts: .legacy.retweet_count, favs: .legacy.favorite_count,
      views: .views.count, src: (.source | str),
      loc: ([$u.legacy.location, $u.location.location] | map(select(type == "string")) | first // ""),
      bw: (.has_birdwatch_notes == true), id: (.legacy.id_str // .rest_id) }
    end;

(.data.tweetResult.result | norm) as $t
| if $t == null then "tweet unavailable" else
  $t
  | (if .vtype == "Business" then " " + color("38;5;220")
     elif .vtype == "Government" then " " + color("38;5;245")
     elif .blue then " " + color("38;5;33")
     else "" end) as $check
  | (try ((.views // 0) | tonumber) catch 0) as $views
  | (.src | gsub("<[^>]*>";"")) as $src
  | (. as $r | $r.text | expand($r.urls; $r.media) | gsub("&amp;";"&") | gsub("  ";" ")) as $text
  | [ "↳ \(.replies | commas) ⇅ \(.rts | commas) ♥ \(.favs | commas)\(if $views > 0 then " 🡕 \($views | commas)" else "" end)",
      (if $src != "" then $src else empty end),
      (if .loc != "" then .loc else empty end),
      (if .bw then "𝚋𝚒𝚛𝚍𝚠𝚊𝚝𝚌𝚑 𝚗𝚘𝚝𝚎" else empty end),
      "https://twitter.com/\(.sn)/status/\(.id)"
    ] as $parts
  | "@\(.sn) (\(.name))\($check): \($text)\(if .limited then " [\(.limited)]" else "" end) | \($parts | join(" | "))"
  end
JQ
)

printf '%s' "$json" | jq -r "$jq_prog" |
  sed -e ':a;N;$!ba;s/\n/ /g' -e 's/  / /g;s/\&amp;/\&/g' |
  sed 's/\\n\\n/ /g;s/\\n/ /g;s/^\"//;s/\"$//;s/\\"/"/g;s/  / /g' 
