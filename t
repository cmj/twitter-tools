#!/bin/bash
# usage: t [-a|-auth] [-r|-raw] [tweet_id or url] (guest/SSR is the default)
# guest mode is slow, won't return birdwatch info and stats are lagged.

# source session envars (x_csrf_token auth_token)
# much faster response vs parsing SSR
. ~/.env-twitter 2>/dev/null
#x_csrf_token=""
#auth_token=""

guest=1
raw=0
while [ $# -gt 0 ]; do
  case "$1" in
    -g|-guest|--guest) guest=1; shift ;;
    -a|-auth|--auth)   guest=0; shift ;;
    -r|-raw|--raw)     raw=1; shift ;;
    *) break ;;
  esac
done

input="${1%#*}"
input="${input%%\?*}"
id="${input##*/}"

ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
bearer_token="AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: ${ua}" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

api='https://api.twitter.com/graphql/sCU6ckfHY0CyJ4HFjPhjtg/TweetResultByRestId'
variables='{"count":1,"withSafetyModeUserFields":true,"includePromotedContent":true,"withQuickPromoteEligibilityTweetFields":true,"withVoice":true,"withV2Timeline":true,"withDownvotePerspective":false,"withBirdwatchNotes":true,"withCommunity":true,"withSuperFollowsUserFields":true,"withReactionsMetadata":false,"withReactionsPerspective":false,"withSuperFollowsTweetFields":true,"isMetatagsQuery":false,"withReplays":true,"withClientEventToken":false,"withAttachments":true,"withConversationQueryHighlights":true,"withMessageQueryHighlights":true,"withMessages":true,"tweetId":"'"${id}"'"}'
features='{"creator_subscriptions_tweet_preview_api_enabled":true,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"tweetypie_unmention_optimization_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"tweet_with_visibility_results_prefer_gql_media_interstitial_enabled":true,"rweb_video_timestamps_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_enhance_cards_enabled":false}'
fieldToggles='{"withArticleRichContentState":true,"withArticlePlainText":true}'

if [ -z "$id" ]; then
  cat << eof
usage: ${0##*/} [option] [tweet_id or url]
  default: no auth, parse the server-side rendered page (-g[uest] is accepted)
  option: -a[uth]  use the authenticated GraphQL API instead
          -r[aw]   raw json dump
eof
  exit 1
fi

# Guest mode: the page is server-side rendered (seroval/TanStack stream, JS object
# literals rather than JSON). Pull out the TweetResultByRestId result and convert
# it to JSON.
guest_extract_pl=$(cat <<'PERL'
my $h = <STDIN>;
while ($h =~ /(?=\{kind:"GraphQLRequestStream\.Completed")(?<o>\{(?:[^{}"]++|"(?:[^"\\]|\\.)*+"|(?&o))*+\})/g) {
  my $s = $+{o};
  next unless index($s, "tweet_result_by_rest_id") >= 0;
  $s =~ s{("(?:[^"\\]|\\.)*+")|(\$R\[\d+\]=)|(!0)|(!1)|(void 0)|([A-Za-z_\$][\w\$]*)(?=:)}{
    if (defined $1) {
      my $str = $1;
      $str =~ s{\\(?:x([0-9A-Fa-f]{2})|(.))}{ defined $1 ? sprintf("\\u00%s", $1) : ($2 eq "'" ? "'" : "\\$2") }gse;
      $str
    } elsif (defined $2) { "" }
    elsif (defined $3) { "true" }
    elsif (defined $4) { "false" }
    elsif (defined $5) { "null" }
    else { "\"$6\"" }
  }gse;
  print "$s\n";
  last;
}
PERL
)

if [ "$guest" -eq 1 ]; then
  mode=guest
  case "$input" in
    *://*/*/status/*) page="https://x.com/${input#*://*/}" ;;
    *)                page="https://x.com/i/status/${id}" ;;
  esac
  json=$(curl -s -L -A "$ua" -H "Accept: text/html" "$page" \
    | perl -0777 -e "$guest_extract_pl" \
    | jq -c '.result.value' 2>/dev/null)
  if [ -z "$json" ] || [ "$json" = "null" ]; then
    echo "${0##*/}: no tweet data found" >&2
    exit 1
  fi
else
  mode=authed
  json=$(curl -s -G "${header[@]}" ${api} \
    --data-urlencode "variables=${variables}" \
    --data-urlencode "features=${features}" \
    --data-urlencode "fieldToggles=${fieldToggles}")
fi

if [ "$raw" -eq 1 ]; then
  printf '%s\n' "$json" | jq . 2>/dev/null || printf '%s\n' "$json"
  exit 0
fi

jq_prog=$(cat <<'JQ'
def commas: tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",");
def color($c): "\u001b[\($c)m✓\u001b[0m";
def str: if type == "string" then . else "" end;

# authed GraphQL (legacy-shaped) -> common record
def norm_authed:
  (if .tweet then .tweet else . end)
  | .core.user_results.result as $u
  | if $u == null then null else
    { sn: $u.legacy.screen_name, name: $u.legacy.name,
      vtype: ($u.legacy.verified_type // ""), blue: ($u.is_blue_verified == true),
      text: .legacy.full_text, limited: .legacy.limited_actions,
      replies: .legacy.reply_count, rts: .legacy.retweet_count, favs: .legacy.favorite_count,
      views: .views.count, src: (.source | str), loc: ($u.legacy.location | str),
      bw: (.has_birdwatch_notes == true), id: .legacy.id_str }
    end;

# guest SSR page (new-shaped) -> common record
def norm_guest:
  (if .tweet then .tweet else . end)
  | .core.user_results.result as $u
  | if $u == null then null else
    { sn: $u.core.screen_name, name: $u.core.name,
      vtype: ($u.verification.verified_type // $u.legacy.verified_type // ""),
      blue: ($u.verification.is_blue_verified == true),
      text: .details.full_text, limited: .legacy.limited_actions,
      replies: .counts.reply_count, rts: .counts.retweet_count, favs: .counts.favorite_count,
      views: .views.count, src: (.source | str),
      loc: ([$u.core.location, $u.legacy.location, $u.location] | map(select(type == "string")) | first // ""),
      bw: (.has_birdwatch_notes == true), id: .rest_id }
    end;

(if $mode == "guest" then (.data.tweet_result_by_rest_id.result | norm_guest)
 else (.data.tweetResult.result | norm_authed) end) as $t
| if $t == null then "tweet unavailable" else
  $t
  | (if .vtype == "Business" then " " + color("38;5;220")
     elif .vtype == "Government" then " " + color("38;5;245")
     elif .blue then " " + color("38;5;33")
     else "" end) as $check
  | (try ((.views // 0) | tonumber) catch 0) as $views
  | (.src | gsub("<[^>]*>";"")) as $src
  | [ "↳ \(.replies | commas) ⇅ \(.rts | commas) ♥ \(.favs | commas)\(if $views > 0 then " 🡕 \($views | commas)" else "" end)",
      (if $src != "" then $src else empty end),
      (if .loc != "" then .loc else empty end),
      (if .bw then "𝚋𝚒𝚛𝚍𝚠𝚊𝚝𝚌𝚑 𝚗𝚘𝚝𝚎" else empty end),
      "https://twitter.com/\(.sn)/status/\(.id)"
    ] as $parts
  | "@\(.sn) (\(.name))\($check): \(.text | gsub("&amp;";"&") | gsub("  ";" "))\(if .limited then " [\(.limited)]" else "" end) | \($parts | join(" | "))"
  end
JQ
)

printf '%s' "$json" | jq -r --arg mode "$mode" "$jq_prog" |
  sed -e ':a;N;$!ba;s/\n/ /g' -e 's/  / /g;s/\&amp;/\&/g' |
  sed 's/\\n\\n/ /g;s/\\n/ /g;s/^\"//;s/\"$//;s/\\"/"/g;s/  / /g' |
  sed 's/[rR]etard/\[slur\]/g' 2>/dev/null
