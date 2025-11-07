#!/bin/bash
# playback live xSpaces audio feed
# archive HLS url if user disables playback feature

# source `auth_token` and `x_csrf_token` 
source ~/.env-twitter

media_id=$1
bearer_token='AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF'
header=(-H "Authorization: Bearer ${bearer_token}" -H "User-Agent: Twitterbot" -H "X-Csrf-Token: ${x_csrf_token}" -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}")
url="https://x.com/i/api/1.1/live_video_stream/status/${media_id}"
stream=$(curl -s "${header[@]}" "${url}" | jq -r .source.noRedirectPlaybackUrl)

# archive the stream url for later use if host disables "replay" feature  
#d=$(date -d '-1 day' +"%Y%m%d-%H%M%S")
#echo "${stream}" > "/home/cmj/dev/twitter/spaces/$id-$d.m3u8"

# mpv, vlc, mplayer
mpv --msg-level=ffmpeg=no "${stream}"

