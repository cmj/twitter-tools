#!/bin/bash
# fully render tweets with images in kitty terminal, defaults to guest/ssr (no auth)
# -a (auth) - faster and enables source label
# requires 't' https://github.com/cmj/twitter-tools/raw/main/t
# optional: apt install boxes (for wrapping tweets, quotes, replies)
# usage: kitty-tweet.sh [-a|-g] [-b] [-S] [id | url | @user [n]]

MAXW=${MAXW:-74}
MAXH=${MAXH:-12}
MAXIMG=${MAXIMG:-4}
MAXQLINES=${MAXQLINES:-6}
SHOW_PARENT=${SHOW_PARENT:-1}
SHOW_SOURCE=${SHOW_SOURCE:-1}

usage() {
  echo "usage: ${0##*/} [-a|-g] [-b] [-S] [id | url | @user [n]]"
  echo "  -a auth api   -g guest/ssr (default)   -b frame with boxes -d ansi-rounded"
  echo "  -S skip the extra source label request (-a only, on by default)"
  echo "  env: MAXW=$MAXW MAXH=$MAXH MAXIMG=$MAXIMG MAXQLINES=$MAXQLINES SHOW_PARENT=$SHOW_PARENT SHOW_SOURCE=$SHOW_SOURCE"
}

topts=() boxes=0
while [ $# -gt 0 ]; do
  case $1 in
    -a|-auth|--auth)   topts+=(-a) ;;
    -g|-guest|--guest) topts+=(-g) ;;
    -b|-box|-boxes|--box|--boxes) boxes=1 ;;
    -S|-nosource|--no-source) SHOW_SOURCE=0 ;;
    -h|-help|--help)   usage; exit 0 ;;
    *) break ;;
  esac
  shift
done
set -- "${@:-20}"

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) tcmd=t miss=0
command -v t >/dev/null || { [ -x "$here/t" ] && tcmd=$here/t; }
need() { command -v "$1" >/dev/null || { echo "${0##*/}: $1 not found. $2" >&2; miss=1; }; }
need kitty "https://sw.kovidgoyal.net/kitty/binary/ (brew install --cask kitty), run this inside kitty"
need jq "apt install jq | brew install jq"
[ "$tcmd" = t ] && need t "get the t script from https://github.com/cmj/twitter-tools (download t, chmod +x t, put it in PATH or next to this script)"
if ((boxes)); then
  need boxes "apt install boxes | brew install boxes | https://boxes.thomasjensen.com (or drop -b)"
  command -v boxes >/dev/null && ! echo x | boxes -d ansi-rounded >/dev/null 2>&1 &&
    { echo "${0##*/}: boxes has no ansi-rounded design, upgrade it (or drop -b)" >&2; miss=1; }
fi
((miss)) && exit 1

[ "$(locale charmap 2>/dev/null)" = UTF-8 ] || {
  export LC_ALL=en_US.UTF-8
  [ "$(locale charmap 2>/dev/null)" = UTF-8 ] || export LC_ALL=C.UTF-8
}

cols=$(tput cols 2>/dev/null || echo 80) rows=$(tput lines 2>/dev/null || echo 24)
W=$((cols < MAXW ? cols : MAXW)); ((W < 36)) && W=36
CW=$((W-4)) GUT=6 TW=$((CW-6)) G='      ' frame=2

jq_prog=$(cat <<'JQ'
def commas: tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",");
def num: (. // 0) | (tonumber? // 0);
def s: if . == null then "" else tostring end;

def base:
  (if type == "object" and has("tweet") then .tweet else . end) as $t
  | ($t.core.user_results.result // {}) as $u
  | ($t.note_tweet.note_tweet_results.result.text // $t.legacy.full_text // $t.details.full_text // "") as $text
  | ($t.note_tweet.note_tweet_results.result.entity_set.urls // $t.legacy.entities.urls // $t.url_entities // []) as $urls
  | ($t.legacy.created_at // null) as $c
  | (($t.card.legacy.binding_values // $t.card.binding_values // [])
     | if type == "array" then (map({(.key): .value}) | add // {}) else . end) as $bv
  | (($bv.card_url.string_value // $t.card.legacy.url // "") | s) as $curl
  | ([$bv.summary_photo_image_large, $bv.photo_image_full_size_large, $bv.summary_photo_image,
      $bv.thumbnail_image_large, $bv.thumbnail_image]
     | map(select(. != null) | .image_value.url // empty) | first // "") as $cimg
  | [($t.media_entities2 // $t.legacy.extended_entities.media // $t.legacy.entities.media // [])[]
     | .media_url_https | select(. != null)] as $media
  | {
      id:     (($t.rest_id // $t.legacy.id_str // "") | s),
      name:   (($u.legacy.name // $u.core.name // "") | s),
      sn:     (($u.legacy.screen_name // $u.core.screen_name // "") | s),
      vtype:  (($u.verification.verified_type // $u.legacy.verified_type // "") | s),
      blue:   (($u.is_blue_verified // $u.verification.is_blue_verified // false) | tostring),
      avatar: (($u.legacy.profile_image_url_https // $u.avatar.image_url // "") | s),
      text:   (reduce $urls[] as $e ($text;
                 if ($e.url // "") == "" then .
                 elif $e.url == $curl and ($e.display_url // "") != "" then split($e.url) | join($e.display_url)
                 elif ($e.expanded_url // "") != "" then split($e.url) | join($e.expanded_url)
                 else . end)
               | gsub("\\s*https://t\\.co/[A-Za-z0-9]+"; "")
               | gsub("&amp;"; "&") | gsub("&lt;"; "<") | gsub("&gt;"; ">")
               | gsub("\\s+$"; "")),
      media:  $media,
      nmedia: ($media | length | tostring),
      card_title: (($bv.title.string_value // "") | s | gsub("^\\s+|\\s+$"; "")),
      card_desc:  (($bv.description.string_value // "") | s),
      card_dom:   (($bv.vanity_url.string_value // $bv.domain.string_value // "") | s),
      card_img:   $cimg,
      card_link:  ((first($urls[] | select(.url == $curl) | .expanded_url) // $curl) | s),
      ts:     (if $c then ($c | strptime("%a %b %d %H:%M:%S +0000 %Y") | mktime | tostring)
               else (($t.details.created_at_ms // $t.core.created_at_ms // null)
                     | if . then ((tonumber / 1000 | floor) | tostring) else "" end) end),
      replies: (($t.legacy.reply_count    // $t.counts.reply_count)    | num | commas),
      rts:     (($t.legacy.retweet_count  // $t.counts.retweet_count)  | num | commas),
      quotes:  (($t.legacy.quote_count    // $t.counts.quote_count)    | num | commas),
      favs:    (($t.legacy.favorite_count // $t.counts.favorite_count) | num | commas),
      views:   (($t.views.count) | num | commas),
      src:     (($t.source // "") | s | gsub("<[^>]*>"; "") | sub("^Twitter (for )?"; ""))
    };

(.data.tweetResult.result // .data.tweet_result_by_rest_id.result // .) as $r
| ($r | if type == "object" and has("tweet") then .tweet else . end) as $t
| ($t | base) as $m
| ([$t | with_entries(select(.key | test("^quoted"))) | .[]
     | select(type == "object") | (.result // .)] | first // null) as $qn
| (if $qn == null then null else ($qn | base) end) as $q
| ([$t, $t.legacy, $t.details] | map(select(type == "object")
     | (.in_reply_to_status_id_str // .in_reply_to_status_id // empty)) | first // null) as $rt1
| ((if $rt1 != null then $rt1
    else ([$t | with_entries(select(.key | test("^quoted") | not)) | .. | objects
           | (.in_reply_to_status_id_str? // empty)] | first // null) end) | s) as $rt
| ($m | if $q != null and $q.id != "" then
         .text |= gsub("\\s*https?://(x|twitter)\\.com/[^/\\s]+/status/" + $q.id + "\\S*"; "")
       else . end) as $m
| ($m + {reply_to: $rt,
          has_q: (if $q == null or (($q.name == "") and ($q.text == "")) then "0" else "1" end),
          has_card: (if $m.card_title != "" then "1" else "0" end)}) as $mm
| (($mm | to_entries)
   + (if $q == null then [] else ($q | to_entries | map(.key |= ("q_" + .))) end))
| .[]
| "\($px)\(.key)=" + (if (.value | type) == "array" then "(\(.value | @sh))" else (.value | @sh) end)
JQ
)

json=$("$tcmd" -r "${topts[@]}" "$@") || exit 1
fields=$(printf %s "$json" | jq -r --arg px m_ "$jq_prog" 2>/dev/null)
eval "$fields"
[ -z "$fields" ] || [ -z "$m_name$m_sn" ] && { echo "${0##*/}: can't parse tweet ($tcmd -r ${topts[*]} $*)" >&2; exit 1; }

p_name=
if [ -n "$m_reply_to" ] && [ "$SHOW_PARENT" = 1 ]; then
  pf=$("$tcmd" -r "${topts[@]}" "$m_reply_to" 2>/dev/null | jq -r --arg px p_ "$jq_prog" 2>/dev/null)
  [ -n "$pf" ] && eval "$pf"
fi

# auth mode: the client label comes from the v2 conversation endpoint (count=1 keeps it small)
if [[ " ${topts[*]} " == *" -a "* && $SHOW_SOURCE = 1 && -n $m_id ]]; then
  s=$([ -f ~/.env-twitter ] && . ~/.env-twitter
    curl -s -m 8 \
      -H "Authorization: Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA" \
      -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" \
      -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}" \
      "https://api.twitter.com/2/timeline/conversation/$m_id.json?count=1&include_reply_count=true&cards_platform=Web-13&include_entities=1&include_user_entities=1&include_cards=1&send_error_codes=1&tweet_mode=extended&include_ext_alt_text=true" |
    jq -r --arg id "$m_id" '(.globalObjects.tweets[$id].source // ([.globalObjects.tweets[]?.source] | first) // "")
      | gsub("<[^>]*>"; "") | sub("^Twitter (for )?"; "")' 2>/dev/null)
  [ -n "$s" ] && m_src=$s
fi

B=$'\033[1m' D=$'\033[2m' R=$'\033[0m'
SENT=$'\xe2\xa0\x80'   # braille blank: stands in for spaces while boxes runs
L=() OPS=() CARD_ROW=-1 CARD_H=0

pad()   { local n=$(($2-${#1})); ((n<0)) && n=0; printf -v REPLY '%s%*s' "$1" $n ''; }
add()   { r=${#L[@]}; pad "$1" $CW; L+=("$REPLY"); }
sty()   { [ -n "$3" ] && OPS+=("$(($1+2))"$'\t'"$2"$'\t'"$3"); }
rep()   { (($2>0)) || return 0; local s; printf -v s '%*s' $2 ''; printf %s "${s// /$1}"; }
trunc() { local m=$2; ((m<1)) && m=1; if ((${#1}>m)); then printf '%s…' "${1:0:m-1}"; else printf %s "$1"; fi; }
wrap()  { printf '%s\n' "$1" | tr '\t' ' ' | fold -s -w "$2" | sed 's/[[:space:]]*$//'; }
ckcol() {
  case $1 in
    Business)   printf '\033[38;5;220m' ;;
    Government) printf '\033[38;5;245m' ;;
    *) [ "$2" = true ] && printf '\033[38;5;33m' ;;
  esac
}

bl() {   # text width maxlines style indent: wrapped lines inside a box
  local line a=() c=0 more=0
  while IFS= read -r line; do
    ((c++ >= $3)) && { more=1; break; }
    a+=("$line")
  done < <(wrap "$1" $2)
  ((more)) && { line=${a[$3-1]}; ((${#line} >= $2)) && line=${line:0:$2-1}; a[$3-1]="$line…"; }
  for line in "${a[@]}"; do
    pad "$line" $2; add "$5│ $REPLY │"
    [ -n "$4" ] && [ -n "$line" ] && sty $r "$4" "$line"
  done
}

cbox() {   # title desc domain link img: link card, image rows reserved inside the box
  local iw=$((TW-4)) osc=$'\033]8;;'"$4"$'\a' blank i ch
  add "$G╭$(rep ─ $((TW-2)))╮"
  if [ -n "$5" ]; then
    ch=$((rows-1-frame-${#L[@]}-10)); ((ch > MAXH)) && ch=$MAXH
    if ((ch >= 4)); then
      pad "" $iw; blank=$REPLY
      CARD_ROW=${#L[@]} CARD_H=$ch
      for ((i=0; i<ch; i++)); do add "$G│ $blank │"; done
    fi
  fi
  bl "$1" $iw 2 "$B$osc" "$G"
  [ -n "$2" ] && bl "$2" $iw 3 "$D" "$G"
  pad "$3" $iw; add "$G│ $REPLY │"; sty $r "$D$osc" "$3"
  add "$G╰$(rep ─ $((TW-2)))╯"
}

qbox() {   # name sn vtype blue text nmedia
  local n=$1 s=$2 hs=" @$2" ck= st nmx
  local bw=$((TW-2)) iw=$((TW-6)) ind="$G  "
  st=$(ckcol "$3" "$4"); [ -n "$st" ] && ck=" ✓"
  nmx=$(trunc "$n" $((iw-${#ck}-${#hs})))
  add "$ind╭$(rep ─ $((bw-2)))╮"
  pad "$nmx$ck$hs" $iw; add "$ind│ $REPLY │"
  sty $r "$B" "$nmx"; [ -n "$ck" ] && sty $r "$st" ✓; sty $r "$D" "@$s"
  [ -n "$5" ] && bl "$5" $iw $MAXQLINES "" "$ind"
  if (($6 > 0)); then pad "▣ $6 media" $iw; add "$ind│ $REPLY │"; sty $r "$D" "▣ $6 media"; fi
  add "$ind╰$(rep ─ $((bw-2)))╯"
}

date_str=
[ -n "$m_ts" ] && date_str=$(date -d "@$m_ts" '+%b %-d, %Y' 2>/dev/null || date -r "$m_ts" '+%b %-d, %Y' 2>/dev/null)
cst=$(ckcol "$m_vtype" "$m_blue") chk=; [ -n "$cst" ] && chk=" ✓"

nm=$(trunc "$m_name" $((TW-${#chk}-${#date_str}-2)))
left="$G$nm$chk"
pad "" $((CW-${#left}-${#date_str})); sp=$REPLY; [ -z "$sp" ] && sp=' '
add "$left$sp$date_str"
sty $r "$B" "$nm"; [ -n "$chk" ] && sty $r "$cst" ✓; sty $r "$D" "$date_str"
add "$G@$m_sn"; sty $r "$D" "@$m_sn"
add ""

if [ -n "$m_reply_to" ]; then
  if [ -n "$p_name" ]; then
    add "$G↳ Replying to @$p_sn"; sty $r "$D" "↳ Replying to @$p_sn"
    qbox "$p_name" "$p_sn" "$p_vtype" "$p_blue" "$p_text" "$p_nmedia"
  else
    add "$G↳ Reply to tweet $m_reply_to"; sty $r "$D" "↳ Reply to tweet $m_reply_to"
  fi
  add ""
fi

if [ -n "$m_text" ]; then
  while IFS= read -r line; do add "$G$line"; done < <(wrap "$m_text" $TW)
  add ""
fi

if [ "$m_has_card" = 1 ]; then
  cbox "$m_card_title" "$m_card_desc" "$m_card_dom" "$m_card_link" "$m_card_img"
  add ""
fi

if [ "$m_has_q" = 1 ]; then
  qbox "$m_q_name" "$m_q_sn" "$m_q_vtype" "$m_q_blue" "$m_q_text" "$m_q_nmedia"
  add ""
fi

# images are only reserved here; kitty draws them after the text is out
IMG_ROW=-1 IMG_H=0 gap=1
n=${#m_media[@]}; ((n > MAXIMG)) && n=$MAXIMG
if ((n > 0)); then
  h=$((rows-1-frame-${#L[@]}-2)); ((h > MAXH)) && h=$MAXH
  bwid=$(((TW-(n-1)*gap)/n))
  while ((n > 1 && bwid < 8)); do ((n--)); bwid=$(((TW-(n-1)*gap)/n)); done
  if ((h >= 4)); then
    IMG_ROW=${#L[@]} IMG_H=$h
    for ((i=0; i<h; i++)); do add ""; done
    add ""
  fi
fi

stats="↳ $m_replies   ⇅ $m_rts   ❝ $m_quotes   ♥ $m_favs"
[ "$m_views" != 0 ] && stats="$stats   🡕 $m_views"
left="$G$stats"
if [ -n "$m_src" ] && ((${#left}+2+${#m_src} <= CW)); then
  pad "" $((CW-${#left}-${#m_src})); add "$left$REPLY$m_src"; sty $r "$D" "$m_src"
else
  add "$left"
fi
sty $r "$D" "$stats"

if ((boxes)); then
  # boxes eats leading whitespace as indentation, so hide every space from it
  out=$(printf '%s\n' "${L[@]}" | sed "s/ /$SENT/g" | boxes -d ansi-rounded) || { echo "${0##*/}: boxes failed" >&2; exit 1; }
else
  out=$(echo; printf '%s\n' "${L[@]}" | sed 's/ *$//; /./s/^/  /')
fi

clear
printf '%s\n' "$out" | awk -F'\t' -v sent="$SENT" -v rst="$R"$'\033]8;;\a' '
  FILENAME == ARGV[1] { c[$1]++; st[$1,c[$1]] = $2; sb[$1,c[$1]] = $3; next }
  { gsub(sent, " ")
    for (i = 1; i <= c[FNR]; i++)
      if ((p = index($0, sb[FNR,i])) > 0)
        $0 = substr($0, 1, p-1) st[FNR,i] sb[FNR,i] rst substr($0, p + length(sb[FNR,i]))
    print }' <(printf '%s\n' "${OPS[@]}") -
((boxes)) || echo

kitty +icat --clear --place 5x5@2x1 "${m_avatar:-https://pbs.twimg.com/profile_images/2095518370342883328/s4NqVf5Z_normal.jpg}"
((CARD_ROW >= 0)) && kitty +icat --place "$((TW-4))x${CARD_H}@$((2+GUT+2))x$((CARD_ROW+1))" "$m_card_img"
if ((IMG_ROW >= 0)); then
  for ((i=0; i<n; i++)); do
    kitty +icat --align left --place "${bwid}x${IMG_H}@$((2+GUT+i*(bwid+gap)))x$((IMG_ROW+1))" "${m_media[i]}"
  done
fi
printf '\033[%d;1H' $((${#L[@]}+frame+1))
