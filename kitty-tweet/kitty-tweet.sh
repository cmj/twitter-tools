#!/bin/bash
# usage: kitty-tweet.sh [-a|-g] [-R] [-b|-B] [-S] [-d domain] [id | url | @user [n]]   (default 20)
# config: ${XDG_CONFIG_HOME:-~/.config}/kitty-tweet/kitty-tweet.conf  (KEY=value; env overrides it, flags override both)

conf=${TWEET_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/kitty-tweet/kitty-tweet.conf}
if [ -f "$conf" ]; then
  while IFS='=' read -r k v || [ -n "$k" ]; do
    k=${k//[[:space:]]/} v=${v%% #*}
    v=${v#"${v%%[![:space:]]*}"} v=${v%"${v##*[![:space:]]}"} v=${v#[\"\']} v=${v%[\"\']}
    case $k in
      MAXW|MAXH|MAXIMG|MAXQLINES|SHOW_PARENT|SHOW_SOURCE|STRIP_TRACKING|DOMAIN|BOXES|MODE)
        [ -z "${!k}" ] && printf -v "$k" %s "$v" ;;
    esac
  done < "$conf"
fi
MAXW=${MAXW:-74} MAXH=${MAXH:-12} MAXIMG=${MAXIMG:-4} MAXQLINES=${MAXQLINES:-6}
SHOW_PARENT=${SHOW_PARENT:-1} SHOW_SOURCE=${SHOW_SOURCE:-1} STRIP_TRACKING=${STRIP_TRACKING:-1}
DOMAIN=${DOMAIN:-} BOXES=${BOXES:-0} MODE=${MODE:-guest}

usage() {
  echo "usage: ${0##*/} [-a|-g] [-R] [-b|-B] [-S] [-d domain] [id | url | @user [n]]"
  echo "  -a session cookies (@user = tweets+replies)   -g guest token (@user = originals)   (default: MODE=$MODE)"
  echo "  -R guest @user: replies timeline"
  echo "  -b frame with boxes -d ansi-rounded   -B no frame   (default: BOXES=$BOXES)"
  echo "  -S skip the source label request (-a only)"
  echo "  -d domain for x.com links, e.g. nitter.net   (default: DOMAIN=${DOMAIN:-x.com})"
  echo "  config: $conf"
  echo "  keys: MAXW=$MAXW MAXH=$MAXH MAXIMG=$MAXIMG MAXQLINES=$MAXQLINES SHOW_PARENT=$SHOW_PARENT"
  echo "        SHOW_SOURCE=$SHOW_SOURCE STRIP_TRACKING=$STRIP_TRACKING DOMAIN MODE BOXES"
}

topts=(); [ "$MODE" = auth ] && topts=(-a)
case $BOXES in 1|true|yes|on) boxes=1 ;; *) boxes=0 ;; esac
while [ $# -gt 0 ]; do
  case $1 in
    -a|-auth|--auth)   topts+=(-a) ;;
    -g|-guest|--guest) topts+=(-g) ;;
    -R|-replies|--replies) topts+=(-R) ;;
    -b|-box|-boxes|--box|--boxes) boxes=1 ;;
    -B|-nobox|--no-boxes) boxes=0 ;;
    -S|-nosource|--no-source) SHOW_SOURCE=0 ;;
    -d|-domain|--domain) DOMAIN=$2; shift ;;
    -h|-help|--help)   usage; exit 0 ;;
    *) break ;;
  esac
  shift
done
set -- "${@:-20}"
DOMAIN=${DOMAIN#http*://} DOMAIN=${DOMAIN%%/*}
strip=1; [ "$STRIP_TRACKING" = 0 ] && strip=0
auth=0; for o in "${topts[@]}"; do [ "$o" = -a ] && auth=1; [ "$o" = -g ] && auth=0; done

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) tcmd=t miss=0
if [ -x "$here/t" ]; then tcmd=$here/t; else command -v t >/dev/null || tcmd=t; fi
need() { command -v "$1" >/dev/null || { echo "${0##*/}: $1 not found. $2" >&2; miss=1; }; }
need kitty "https://sw.kovidgoyal.net/kitty/binary/ (brew install --cask kitty), run this inside kitty"
need jq "apt install jq | brew install jq"
[ "$tcmd" = t ] && need t "get the t script from https://github.com/cmj/twitter-tools (download t, chmod +x t, put it in PATH or next to this script)"
if ((boxes)); then
  need perl "apt install perl | brew install perl"
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

# link spans travel through the text as \1href\2display\3
jq_prog=$(cat <<'JQ'
def commas: tostring | [while(length>0; .[:-3]) | .[-3:]] | reverse | join(",");
def num: (. // 0) | (tonumber? // 0);
def s: if . == null then "" else tostring end;
def mk($h; $d): "\u0001" + $h + "\u0002" + $d + "\u0003";
def todom: if $dom == "" then . else sub("^https?://((www|mobile)\\.)?(x|twitter)\\.com(?=[/?#]|$)"; "https://" + $dom) end;
def xurl($p): "https://" + (if $dom == "" then "x.com" else $dom end) + $p;
def tracked: "^(utm_[^=]*|fbclid|gclid|dclid|gbraid|wbraid|msclkid|yclid|twclid|igshid|igsh|mc_[ce]id|_hs[a-z]+|mkt_tok|vero_id|oly_[a-z_]+|ocid|ncid|cmpid|s_cid|ref_src|ref_url)(=|$)";
def cleanurl:
  ([capture("^(?<b>[^?#]*)\\?(?<q>[^#]*)(?<f>#.*)?$")] | first // null) as $c
  | if $strip == 0 or $c == null then . else
      ($c.b | test("^https?://([a-z0-9-]+\\.)*(x|twitter)\\.com/")) as $isx
      | ($c.b | test("^https?://([a-z0-9-]+\\.)*(youtu\\.be|youtube\\.com|spotify\\.com)/")) as $iss
      | ($c.q | split("&") | map(select(
          (test(tracked; "i") | not)
          and (($isx | not) or (test("^(s|t|src)(=|$)") | not))
          and (($iss | not) or (test("^si(=|$)") | not)))) | join("&")) as $q
      | $c.b + (if $q != "" then "?" + $q else "" end) + ($c.f // "")
    end;
def rich:
  gsub("(?<u>https?://[^\\s\u0001-\u0004]*[^\\s.,;:!?)\\]\"'’”\u0001-\u0004])";
       (.u | cleanurl | todom) as $h | mk($h; $h))
  | gsub("(?<m>\u0001[^\u0003]*\u0003)|(?<![\\w@/])@(?<n>[A-Za-z0-9_]{1,15})";
       if .m then .m else mk(xurl("/" + .n); "@" + .n) end);

def base($qid):
  (if type == "object" and has("tweet") then .tweet else . end) as $t
  | ($t.core.user_results.result // {}) as $u
  | ($u.legacy.screen_name // $u.core.screen_name // "" | s) as $sn
  | ($t.rest_id // $t.legacy.id_str // "" | s) as $id
  | ($t.note_tweet.note_tweet_results.result.text // $t.legacy.full_text // $t.details.full_text // "") as $text
  | ($t.note_tweet.note_tweet_results.result.entity_set.urls // $t.legacy.entities.urls // $t.url_entities // []) as $urls
  | ($t.legacy.created_at // null) as $c
  | (($t.card.legacy.binding_values // $t.card.binding_values // [])
     | if type == "array" then (map({(.key): .value}) | add // {}) else . end
     | if type == "object" then . else {} end) as $bv
  | (($bv.card_url.string_value // $t.card.legacy.url // "") | s) as $curl
  | (($t.card.legacy.name // $t.card.name // "") | s) as $cname
  | ([$urls[] | .expanded_url // empty
      | select(test("^https?://(www\\.)?(x|twitter)\\.com/i/(broadcasts|spaces)/[A-Za-z0-9]+"))] | first // null) as $bsu
  | (if $bsu != null then ($bsu | if test("/spaces/") then "Space" else "Broadcast" end)
     elif ($cname | test("broadcast|audiospace|periscope"; "i"))
       then (if ($cname | test("space"; "i")) then "Space" else "Broadcast" end)
     else null end) as $bkind
  | ([$bv.summary_photo_image_large, $bv.photo_image_full_size_large, $bv.summary_photo_image,
      $bv.thumbnail_image_large, $bv.thumbnail_image]
     | map(select(. != null) | .image_value.url // empty) | first // "") as $cimg0
  | (if $cimg0 == "" and $bkind != null
     then ([$bv | .[]? | .image_value.url? // empty] | first // "") else $cimg0 end) as $cimg
  | (first($urls[] | select(.url == $curl) | .expanded_url) // $bsu // $curl | s | cleanurl | todom) as $clink
  | (($bv.title.string_value // $bv.broadcast_title.string_value // "") | s | gsub("^\\s+|\\s+$"; "")) as $ct0
  | (if $ct0 == "" and $bkind != null then $bkind else $ct0 end) as $ctitle
  | ($bv.description.string_value // (if $bv.broadcaster_display_name then "by " + $bv.broadcaster_display_name.string_value else "" end) | s) as $cdesc
  | (if $bkind != null then ($clink | sub("^https?://"; ""))
     else (($bv.vanity_url.string_value // $bv.domain.string_value // "") | s) end) as $cdom
  | (reduce $urls[] as $e ($text;
       if ($e.url // "") == "" then .
       elif $e.url == $curl then split($e.url) | join("\u0004")
       elif ($e.expanded_url // "") != "" then split($e.url) | join($e.expanded_url)
       else . end)
     | gsub("\\s*https://t\\.co/[A-Za-z0-9]+"; "")
     | gsub("&amp;"; "&") | gsub("&lt;"; "<") | gsub("&gt;"; ">")
     | (if $qid != "" then gsub("\\s*https?://(x|twitter)\\.com/[^/\\s]+/status/" + $qid + "\\S*"; "") else . end)
     | gsub("\\s+$"; "")
     | rich
     | (if $clink != "" then split("\u0004")
          | join(mk($clink; (first($urls[] | select(.url == $curl) | .display_url // empty) // $clink)))
        else . end)) as $body
  | [($t.media_entities2 // $t.legacy.extended_entities.media // $t.legacy.entities.media // [])[]
     | select(.media_url_https != null)] as $med
  | ($t.birdwatch_pivot // null) as $bp
  | (if $bp == null then "" else
       ($bp.footer.text // "") as $ft | (($bp.footer.entities // [])[0]) as $fe
       | (if $fe != null and ($fe.ref.url // "") != ""
          then $ft[:$fe.from_index] + mk($fe.ref.url; $ft[$fe.from_index:$fe.to_index]) + $ft[$fe.to_index:]
          else $ft end) | gsub("  +"; " ")
     end) as $bwfoot
  | {
      id: $id,
      name:   (($u.legacy.name // $u.core.name // "") | s),
      sn:     $sn,
      url:    xurl("/" + $sn + "/status/" + $id),
      purl:   xurl("/" + $sn),
      vtype:  (($u.verification.verified_type // $u.legacy.verified_type // "") | s),
      blue:   (($u.is_blue_verified // $u.verification.is_blue_verified // false) | tostring),
      avatar: (($u.legacy.profile_image_url_https // $u.avatar.image_url // "") | s),
      text:   $body,
      media:  ($med | map(.media_url_https)),
      mtypes: ($med | map(.type // "photo")),
      mlinks: ($med | map(if (.type == "video" or .type == "animated_gif")
                          then (([.video_info.variants[]? | select(.content_type == "video/mp4")]
                                 | max_by(.bitrate // 0) | .url) // .expanded_url // .media_url_https)
                          else (.media_url_https + "?name=orig") end)),
      ai:     (($t.content_disclosure.ai_generated_disclosure.has_ai_generated_media // false) | tostring),
      card_title: $ctitle,
      card_desc:  $cdesc,
      card_dom:   $cdom,
      card_img:   $cimg,
      card_link:  $clink,
      has_bw:   (if $bp == null then "0" else "1" end),
      bw_title: (($bp.title // $bp.shorttitle // "") | s),
      bw_text:  (($bp.note.summary.text // $bp.subtitle.text // "") | s | gsub("&amp;"; "&") | gsub("\\s+$"; "") | rich),
      bw_url:   (($bp.destination_url // "") | s),
      bw_foot:  $bwfoot,
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
| ([$t.quoted_status_result.result?]
   + [$t | with_entries(select(.key | test("^quoted"))) | .[]
     | select(type == "object") | (.result // .)] | map(select(. != null)) | first // null) as $qn
| (if $qn == null then null else ($qn | base("")) end) as $q
| ($t | base(if $q == null then "" else $q.id end)) as $m
| ([$t, $t.legacy, $t.details] | map(select(type == "object")
     | (.in_reply_to_status_id_str // .in_reply_to_status_id // empty)) | first // null) as $rt1
| ((if $rt1 != null then $rt1
    else ([$t | with_entries(select(.key | test("^quoted") | not)) | .. | objects
           | (.in_reply_to_status_id_str? // empty)] | first // null) end) | s) as $rt
| ($m + {reply_to: $rt,
          has_q: (if $q == null or (($q.name == "") and ($q.text == "")) then "0" else "1" end),
          has_card: (if $m.card_title != "" then "1" else "0" end)}) as $mm
| (($mm | to_entries)
   + (if $q == null then [] else ($q | to_entries | map(.key |= ("q_" + .))) end))
| .[]
| "\($px)\(.key)=" + (if (.value | type) == "array" then "(\(.value | @sh))" else (.value | @sh) end)
JQ
)
jqrun() { jq -r --arg px "$1" --arg dom "$DOMAIN" --argjson strip $strip "$jq_prog" 2>/dev/null; }

json=$("$tcmd" -r "${topts[@]}" "$@") || exit 1
fields=$(printf %s "$json" | jqrun m_)
eval "$fields"
[ -z "$fields" ] || [ -z "$m_name$m_sn" ] && { echo "${0##*/}: can't parse tweet ($tcmd -r ${topts[*]} $*)" >&2; exit 1; }

p_name=
if [ -n "$m_reply_to" ] && [ "$SHOW_PARENT" = 1 ]; then
  pf=$("$tcmd" -r "${topts[@]}" "$m_reply_to" 2>/dev/null | jqrun p_)
  [ -n "$pf" ] && eval "$pf"
fi

if ((auth)) && [ "$SHOW_SOURCE" = 1 ] && [ -n "$m_id" ]; then
  s=$("$tcmd" -a -s "$m_id" 2>/dev/null)
  [ -n "$s" ] && m_src=$s
fi

B=$'\033[1m' D=$'\033[2m' R=$'\033[0m'
SENT=$'\xe2\xa0\x80'   # braille blank: stands in for spaces while boxes runs
US=$'\x1f' RSEP=$'\x1e'

pad()   { local n=$(($2-${#1})); ((n<0)) && n=0; printf -v REPLY '%s%*s' "$1" $n ''; }
add()   { r=${#L[@]}; pad "$1" $CW; L+=("$REPLY"); }
sty()   { [ -n "$3" ] && OPS+=("$(($1+2))"$'\t'"$2"$'\t'"$3"$'\t'"$4"); }   # row style text [text-before]
place() { PL+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\t'"$(($5+1))"$'\t'"$6"); }  # url w h x row align
rep()   { (($2>0)) || return 0; local s; printf -v s '%*s' $2 ''; printf %s "${s// /$1}"; }
trunc() { local m=$2; ((m<1)) && m=1; if ((${#1}>m)); then printf '%s…' "${1:0:m-1}"; else printf %s "$1"; fi; }
osc()   { printf '\033]8;;%s\a' "$1"; }
get()   { local v=$1$2; printf -v "$3" %s "${!v}"; }
ckcol() {
  case $1 in
    Business)   printf '\033[38;5;220m' ;;
    Government) printf '\033[38;5;245m' ;;
    *) [ "$2" = true ] && printf '\033[38;5;33m' ;;
  esac
}
reltime() {   # epoch -> 12s / 12m / 3h inside a day, else Oct 21, 2026
  local d=$(($(date +%s)-$1))
  if   ((d >= 0 && d < 60));    then echo "${d}s"
  elif ((d >= 0 && d < 3600));  then echo "$((d/60))m"
  elif ((d >= 0 && d < 86400)); then echo "$((d/3600))h"
  else date -d "@$1" '+%b %-d, %Y' 2>/dev/null || date -r "$1" '+%b %-d, %Y' 2>/dev/null
  fi
}

# wrap text that carries link markers; RL[] = lines, RS[] = link spans "start US len US href" joined by RSEP
rwrap() {
  local t=${1//$'\t'/ } w=$2 i c st=0 href= p=0 j e np nl lim soft n line sp cur h cs
  local -a ch=() hr=()
  RL=() RS=()
  for ((i=0; i<${#t}; i++)); do
    c=${t:i:1}
    if   [ "$c" = $'\001' ]; then st=1 href=
    elif [ "$c" = $'\002' ]; then st=2
    elif [ "$c" = $'\003' ]; then st=0 href=
    elif ((st == 1)); then href+=$c
    else ch+=("$c"); if ((st == 2)); then hr+=("$href"); else hr+=(""); fi
    fi
  done
  n=${#ch[@]}
  while ((p < n)); do
    nl=-1 soft=0 lim=$((p+w+1)); ((lim > n)) && lim=$n
    for ((j=p; j<lim; j++)); do [ "${ch[j]}" = $'\n' ] && { nl=$j; break; }; done
    if ((nl >= 0)); then e=$nl np=$((nl+1))
    elif ((n-p <= w)); then e=$n np=$n
    elif [ "${ch[p+w]}" = " " ]; then e=$((p+w)) np=$((p+w+1)) soft=1
    else
      e=-1; for ((j=p+w-1; j>p; j--)); do [ "${ch[j]}" = " " ] && { e=$j; break; }; done
      if ((e >= 0)); then np=$((e+1)) soft=1; else e=$((p+w)) np=$((p+w)); fi
    fi
    ((soft)) && while ((np < n)) && [ "${ch[np]}" = " " ]; do ((np++)); done
    while ((e > p)) && [ "${ch[e-1]}" = " " ]; do ((e--)); done
    line= sp= cur= cs=0
    for ((j=p; j<e; j++)); do
      line+=${ch[j]}; h=${hr[j]}
      if [ "$h" != "$cur" ]; then
        [ -n "$cur" ] && sp+=${sp:+$RSEP}"$cs$US$((j-p-cs))$US$cur"
        cur=$h cs=$((j-p))
      fi
    done
    [ -n "$cur" ] && sp+=${sp:+$RSEP}"$cs$US$((e-p-cs))$US$cur"
    RL+=("$line") RS+=("$sp")
    p=$np
  done
}

# wrapped, clickable text: text width maxlines style lead tail (one add per line, link ops right to left)
rbl() {
  local k n i line sp f st len href pos cut=0 style text
  local -a a ss sl sh segs
  rwrap "$1" $2
  n=${#RL[@]}; if (($3 > 0 && n > $3)); then n=$3 cut=1; fi
  for ((k=0; k<n; k++)); do
    line=${RL[k]} sp=${RS[k]}
    if ((cut && k == n-1)); then ((${#line} >= $2)) && line=${line:0:$2-1}; line+=…; fi
    pad "$line" $2; add "$5$REPLY$6"
    ss=() sl=() sh=() segs=() pos=0
    if [ -n "$sp" ]; then
      IFS=$RSEP read -ra a <<< "$sp"
      for f in "${a[@]}"; do
        IFS=$US read -r st len href <<< "$f"
        ((st+len <= ${#line})) && { ss+=("$st"); sl+=("$len"); sh+=("$href"); }
      done
    fi
    for ((i=0; i<${#ss[@]}; i++)); do
      ((ss[i] > pos)) && segs+=("$pos$US$((ss[i]-pos))$US")
      segs+=("${ss[i]}$US${sl[i]}$US${sh[i]}")
      pos=$((ss[i]+sl[i]))
    done
    ((pos < ${#line})) && segs+=("$pos$US$((${#line}-pos))$US")
    for ((i=${#segs[@]}-1; i>=0; i--)); do
      IFS=$US read -r st len href <<< "${segs[i]}"
      style=$4; [ -n "$href" ] && style+=$(osc "$href")
      text=${line:st:len}
      [ -n "$style" ] && sty $r "$style" "$text" "$5${line:0:st}"
    done
  done
}

# clickable media labels from ml[] / mt[]: lead tail width
medrow() {
  local i line= lab; local -a lb=()
  for ((i=0; i<${#ml[@]}; i++)); do
    case ${mt[i]} in video|animated_gif) lab="▶ $((i+1))" ;; *) lab="▣ $((i+1))" ;; esac
    lb+=("$lab"); line+="$lab  "
  done
  pad "${line%  }" $3; add "$1$REPLY$2"
  for ((i=0; i<${#lb[@]}; i++)); do sty $r "$D$(osc "${ml[i]}")" "${lb[i]}"; done
}

qbox() {   # prefix: m_q_ (quoted) or p_ (replied to)
  local px=$1 n s vt bl t u pu txt ts= ck= st hs nmx hdr bef i k nq bq qh blank
  local bw=$((TW-2)) iw=$((TW-6)) ind="$G  "
  get $px name n; get $px sn s; get $px vtype vt; get $px blue bl; get $px text txt
  get $px ts t; get $px url u; get $px purl pu
  eval "local -a med=(\"\${${px}media[@]}\") ml=(\"\${${px}mlinks[@]}\") mt=(\"\${${px}mtypes[@]}\")"
  st=$(ckcol "$vt" "$bl"); [ -n "$st" ] && ck=" ✓"
  [ -n "$t" ] && ts=$(reltime "$t")
  hs=" @$s"
  nmx=$(trunc "$n" $((iw-${#ck}-${#hs}-${#ts}-2)))
  hdr="$nmx$ck$hs"; pad "" $((iw-${#hdr}-${#ts})); bef="$ind│ $hdr$REPLY"; hdr="$hdr$REPLY$ts"
  add "$ind╭$(rep ─ $((bw-2)))╮"
  pad "$hdr" $iw; add "$ind│ $REPLY │"
  [ -n "$ts" ] && sty $r "$D$(osc "$u")" "$ts" "$bef"
  sty $r "$B" "$nmx"; [ -n "$ck" ] && sty $r "$st" ✓; sty $r "$D$(osc "$pu")" "@$s"
  [ -n "$txt" ] && rbl "$txt" $iw $MAXQLINES "" "$ind│ " " │"
  if ((${#med[@]} > 0 && HCAP >= 4)); then
    qh=$((HCAP < 9 ? HCAP : 9)) nq=${#med[@]}; ((nq > MAXIMG)) && nq=$MAXIMG
    bq=$(((iw-nq+1)/nq)); while ((nq > 1 && bq < 8)); do ((nq--)); bq=$(((iw-nq+1)/nq)); done
    for ((i=0; i<nq; i++)); do place "${med[i]}" $bq $qh $((2+GUT+4+i*(bq+1))) ${#L[@]} left; done
    pad "" $iw; blank=$REPLY
    for ((k=0; k<qh; k++)); do add "$ind│ $blank │"; done
  fi
  ((${#ml[@]})) && medrow "$ind│ " " │" $iw
  add "$ind╰$(rep ─ $((bw-2)))╯"
}

cbox() {   # title desc domain link img
  local iw=$((TW-4)) o i blank; o=$(osc "$4")
  add "$G╭$(rep ─ $((TW-2)))╮"
  if [ -n "$5" ] && ((HCAP >= 4)); then
    pad "" $iw; blank=$REPLY
    place "$5" $iw $HCAP $((2+GUT+2)) ${#L[@]} center
    for ((i=0; i<HCAP; i++)); do add "$G│ $blank │"; done
  fi
  rbl "$1" $iw 2 "$B$o" "$G│ " " │"
  [ -n "$2" ] && rbl "$2" $iw 3 "$D" "$G│ " " │"
  pad "$3" $iw; add "$G│ $REPLY │"; sty $r "$D$o" "$3"
  add "$G╰$(rep ─ $((TW-2)))╯"
}

bwbox() {   # birdwatch note
  local iw=$((TW-4)) o; o=$(osc "$m_bw_url")
  add "$G╭$(rep ─ $((TW-2)))╮"
  rbl "$m_bw_title" $iw 2 "$B$o" "$G│ " " │"
  [ -n "$m_bw_text" ] && rbl "$m_bw_text" $iw $MAXQLINES "" "$G│ " " │"
  [ -n "$m_bw_foot" ] && rbl "$m_bw_foot" $iw 3 "$D" "$G│ " " │"
  add "$G╰$(rep ─ $((TW-2)))╯"
}

build() {
  L=() OPS=() PL=()
  local date_str= cst chk= nm left sp i n bwid gap=1 stats
  local -a ml=() mt=()
  [ -n "$m_ts" ] && date_str=$(reltime "$m_ts")
  cst=$(ckcol "$m_vtype" "$m_blue"); [ -n "$cst" ] && chk=" ✓"
  nm=$(trunc "$m_name" $((TW-${#chk}-${#date_str}-2)))
  left="$G$nm$chk"; pad "" $((CW-${#left}-${#date_str})); sp=$REPLY; [ -z "$sp" ] && sp=' '
  add "$left$sp$date_str"
  [ -n "$date_str" ] && sty $r "$D$(osc "$m_url")" "$date_str" "$left$sp"
  sty $r "$B" "$nm"; [ -n "$chk" ] && sty $r "$cst" ✓
  add "$G@$m_sn"; sty $r "$D$(osc "$m_purl")" "@$m_sn"
  add ""

  if [ -n "$m_reply_to" ]; then
    if [ -n "$p_name" ]; then
      add "$G↳ Replying to @$p_sn"; sty $r "$D" "↳ Replying to @$p_sn"; sty $r "$(osc "$p_purl")" "@$p_sn"
      qbox p_
    else
      add "$G↳ Reply to tweet $m_reply_to"; sty $r "$D$(osc "https://${DOMAIN:-x.com}/i/status/$m_reply_to")" "↳ Reply to tweet $m_reply_to"
    fi
    add ""
  fi

  [ -n "$m_text" ] && { rbl "$m_text" $TW 0 "" "$G" ""; add ""; }
  [ "$m_has_card" = 1 ] && { cbox "$m_card_title" "$m_card_desc" "$m_card_dom" "$m_card_link" "$m_card_img"; add ""; }
  [ "$m_has_q" = 1 ] && { qbox m_q_; add ""; }

  n=${#m_media[@]}; ((n > MAXIMG)) && n=$MAXIMG
  if ((n > 0)); then
    bwid=$(((TW-(n-1)*gap)/n)); while ((n > 1 && bwid < 8)); do ((n--)); bwid=$(((TW-(n-1)*gap)/n)); done
    if ((HCAP >= 4)); then
      for ((i=0; i<n; i++)); do place "${m_media[i]}" $bwid $HCAP $((2+GUT+i*(bwid+gap))) ${#L[@]} left; done
      for ((i=0; i<HCAP; i++)); do add ""; done
    fi
    ml=("${m_mlinks[@]}") mt=("${m_mtypes[@]}"); medrow "$G" "" $TW
    add ""
  fi

  [ "$m_ai" = true ] && { add "$G✨ generated with AI"; sty $r "$D" "✨ generated with AI"; add ""; }
  [ "$m_has_bw" = 1 ] && { bwbox; add ""; }

  stats="↳ $m_replies   ⇅ $m_rts   ❝ $m_quotes   ♥ $m_favs"
  [ "$m_views" != 0 ] && stats="$stats   ılı $m_views"
  left="$G$stats"
  if [ -n "$m_src" ] && ((${#left}+2+${#m_src} <= CW)); then
    pad "" $((CW-${#left}-${#m_src})); add "$left$REPLY$m_src"; sty $r "$D" "$m_src"
  else
    add "$left"
  fi
  sty $r "$D" "$stats"
}

# no room? retry with smaller images, then none
for HCAP in $MAXH 8 5 0; do
  ((HCAP > MAXH)) && continue
  build
  ((${#L[@]}+frame+1 <= rows)) && break
done

if ((boxes)); then
  # boxes eats leading whitespace as indentation, so hide every space from it
  out=$(printf '%s\n' "${L[@]}" | sed "s/ /$SENT/g" | boxes -d ansi-rounded) || { echo "${0##*/}: boxes failed" >&2; exit 1; }
else
  out=$(echo; printf '%s\n' "${L[@]}" | sed 's/ *$//; /./s/^/  /')
fi

wfix() {   # boxes sizes lines by per-codepoint wcwidth, kitty draws emoji clusters 2 cells wide: move the difference out of the last gap
  perl -CSD -ne '
    chomp; my @t = split /(\e\][^\a]*\a|\e\[[0-9;]*m)/; my $d = 0;
    for (my $i = 0; $i < @t; $i += 2) { for my $g ($t[$i] =~ /\X/g) {
      my $w = $g =~ /\x{FE0F}|^[\x{1F1E6}-\x{1F1FF}]{2}|\p{Ea=W}|\p{Ea=F}/ ? 2 : 1;
      $d += $w; $d -= /\p{Ea=W}|\p{Ea=F}/ ? 2 : /[\p{Mn}\p{Me}\p{Cf}]/ ? 0 : 1 for split //, $g } }
    while ($d != 0) { my ($k, $n);
      for my $m (2, 1) { $n = $m; for (my $i = $#t - ($#t % 2); $i >= 0; $i -= 2) { if ($t[$i] =~ / {$n,}/) { $k = $i; last } } last if defined $k }
      last unless defined $k;
      if ($d > 0) { $t[$k] =~ s/( {$n,})(?!.* {$n,})/substr($1, 1)/e; $d-- } else { $t[$k] =~ s/( {$n,})(?!.* {$n,})/$1 /; $d++ }
    }
    print @t, "\n"'
}

clear
printf '%s\n' "$out" | LC_ALL=C awk -F'\t' -v sent="$SENT" -v rst="$R"$'\033]8;;\a' -v boxed=$boxes '
  FILENAME == ARGV[1] { c[$1]++; st[$1,c[$1]] = $2; sb[$1,c[$1]] = $3; bf[$1,c[$1]] = $4; next }
  { gsub(sent, " ")
    for (i = 1; i <= c[FNR]; i++)
      if ((p = index($0, bf[FNR,i] sb[FNR,i])) > 0) {
        p += length(bf[FNR,i])
        $0 = substr($0, 1, p-1) st[FNR,i] sb[FNR,i] rst substr($0, p + length(sb[FNR,i]))
      }
    print }' <(printf '%s\n' "${OPS[@]}") - | { ((boxes)) && wfix || cat; }
((boxes)) || echo

kitty +icat --clear --place 5x5@2x1 "${m_avatar:-https://pbs.twimg.com/profile_images/2095518370342883328/s4NqVf5Z_normal.jpg}"
for pl in "${PL[@]}"; do
  IFS=$'\t' read -r u w h x y a <<< "$pl"
  [ -n "$u" ] && kitty +icat --align "$a" --place "${w}x${h}@${x}x${y}" "$u"
done
printf '\033[%d;1H' $((${#L[@]}+frame+1))
