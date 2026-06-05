#!/bin/bash
# Get timestamp from a 'twimg' (Twitter image) url and return search options to find originating tweet.
# Image is given a snowflake id before the actual tweet; add ~2 seconds to until_time search operator.
# ./twimg2date.sh https://pbs.twimg.com/media/GmeLAsLbYAAPGpk.jpg

input=$(sed -E 's|.*/||;s/.*%2F//' <<< "${1}" | head -c15)
twimg=$(base64 -d <<< "${input}" 2>/dev/null | od -An -tx1 | sed -E 's/ //g;s/.{6}$//')
id=$(bc <<< "ibase=16; ${twimg^^}")
d=$((($id>>22)+1288834974657))
echo id: "$d"
date -d @${d:: -3} '+%F %T %s' | 
  while read date time epoch; do
    echo "Image post date: $date $time"
    echo "Find original tweet using these search options:"
    echo "since_time:$epoch until_time:$(($epoch+2)) filter:twimg"
  done
