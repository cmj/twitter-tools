#!/bin/bash
# usage: t [-a|-auth] [-r|-raw] [tweet_id | url | @user [n]] (guest/SSR is the default)
# guest mode is slow, won't return birdwatch info and stats are lagged.

# source session envars (x_csrf_token auth_token); much faster response vs parsing SSR
[ -f ~/.env-twitter ] && source ~/.env-twitter
#x_csrf_token=$(openssl rand -hex 16)
#auth_token=""

usage() {
  cat << eof
usage: ${0##*/} [option] [tweet_id | url | @user [n]]
  @user [n]  the n-th tweet (default 1 = newest) in a user's timeline
  default: no auth, parse the server-side rendered page (slow)
  option: -a[uth]  use the authenticated GraphQL API instead (fast)
          -r[aw]   raw json dump
          -h[elp]  this help
eof
}

guest=1
raw=0
while [ $# -gt 0 ]; do
  case "$1" in
    -g|-guest|--guest) guest=1; shift ;;
    -a|-auth|--auth)   guest=0; shift ;;
    -r|-raw|--raw)     raw=1; shift ;;
    -h|-help|--help)   usage; exit 0 ;;
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

ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
bearer_token="AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: ${ua}" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")

api='https://api.twitter.com/graphql/sCU6ckfHY0CyJ4HFjPhjtg/TweetResultByRestId'
variables='{"count":1,"withSafetyModeUserFields":true,"includePromotedContent":true,"withQuickPromoteEligibilityTweetFields":true,"withVoice":true,"withV2Timeline":true,"withDownvotePerspective":false,"withBirdwatchNotes":true,"withCommunity":true,"withSuperFollowsUserFields":true,"withReactionsMetadata":false,"withReactionsPerspective":false,"withSuperFollowsTweetFields":true,"isMetatagsQuery":false,"withReplays":true,"withClientEventToken":false,"withAttachments":true,"withConversationQueryHighlights":true,"withMessageQueryHighlights":true,"withMessages":true,"tweetId":"'"${id}"'"}'
features='{"creator_subscriptions_tweet_preview_api_enabled":true,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"tweetypie_unmention_optimization_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"tweet_with_visibility_results_prefer_gql_media_interstitial_enabled":true,"rweb_video_timestamps_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_enhance_cards_enabled":false}'
fieldToggles='{"withArticleRichContentState":true,"withArticlePlainText":true}'

case "$nth" in
  ''|*[!0-9]*|0) echo "${0##*/}: n must be a positive number, got '$nth'" >&2; exit 1 ;;
esac

if [ -z "$id" ]; then
  usage
  exit 1
fi

# server-side rendered
guest_extract_pl=$(cat <<'PERL'
my $h = <STDIN>;
while ($h =~ /(?=\{kind:"GraphQLRequestStream\.Completed")(?<o>\{(?:[^{}"]++|"(?:[^"\\]|\\.)*+"|(?&o))*+\})/g) {
  my $s = $+{o};
  next unless index($s, $ENV{NEEDLE}) >= 0;
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
  if [ -n "$user" ]; then
    page="https://x.com/${user}"
    needle=profile_user_originals_timeline
    select_jq='.result.value.data.user_result_by_screen_name.result.profile_user_originals_timeline.timeline as $tl
      | [ $tl.instructions[]? | select(.__typename == "TimelineAddEntries") | .entries[]?
          | select(.entry_id | startswith("tweet-")) | .content.content.tweet_results.result ] as $t
      | if ($t | length) < $n then {short: ($t | length)}
        else {data: {tweet_result_by_rest_id: {result: $t[$n - 1]}}} end'
  else
    case "$input" in
      *://*/*/status/*) page="https://x.com/${input#*://*/}" ;;
      *)                page="https://x.com/i/status/${id}" ;;
    esac
    needle=tweet_result_by_rest_id
    select_jq='.result.value'
  fi
  json=$(curl -s -L -A "$ua" -H "Accept: text/html" "$page" \
    | NEEDLE="$needle" perl -0777 -e "$guest_extract_pl" \
    | jq -c --argjson n "$nth" "$select_jq" 2>/dev/null)
  short=$(printf '%s' "$json" | jq -r '.short // empty' 2>/dev/null)
  if [ -n "$short" ]; then
    echo "${0##*/}: only $short tweet(s) in @${user}'s page timeline (asked for #$nth)" >&2
    exit 1
  fi
  if [ -z "$json" ] || [ "$json" = "null" ]; then
    echo "${0##*/}: no tweet data found in page (tweet unavailable, blocked, or page layout changed)" >&2
    exit 1
  fi
else
  mode=authed
  if [ -n "$user" ]; then
    echo "${0##*/}: profile lookups (@user) only work in guest mode" >&2
    exit 1
  fi
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

# authed GraphQL (legacy-shaped) -> common record
def norm_authed:
  (if .tweet then .tweet else . end)
  | .core.user_results.result as $u
  | if $u == null then null else
    { sn: $u.legacy.screen_name, name: $u.legacy.name,
      vtype: ($u.legacy.verified_type // ""), blue: ($u.is_blue_verified == true),
      text: (.note_tweet.note_tweet_results.result.text // .legacy.full_text),
      urls: (.note_tweet.note_tweet_results.result.entity_set.urls // .legacy.entities.urls),
      media: (.legacy.extended_entities.media // .legacy.entities.media),
      limited: .legacy.limited_actions,
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
      text: (.note_tweet.note_tweet_results.result.text // .details.full_text),
      urls: (.note_tweet.note_tweet_results.result.entity_set.urls // .url_entities),
      media: .media_entities2,
      limited: .legacy.limited_actions,
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

printf '%s' "$json" | jq -r --arg mode "$mode" "$jq_prog" |
  sed -e ':a;N;$!ba;s/\n/ /g' -e 's/  / /g;s/\&amp;/\&/g' |
  sed 's/\\n\\n/ /g;s/\\n/ /g;s/^\"//;s/\"$//;s/\\"/"/g;s/  / /g' 
