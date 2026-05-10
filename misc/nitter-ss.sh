#!/usr/bin/env bash
# take a screenshot of a tweet
# requires: shot-scraper, imagemagick (to chop navbar)

# nitter instance, see: https://github.com/zedeus/nitter/wiki/Instances
#nitter="https://nitter.net"
nitter="http://nitter.local" 

url="$1"

if [[ -z "$url" ]]; then
  echo -e "Screenshot a tweet from Nitter\nUsage: $0 <url>"
  exit 1
fi

id=${url#*/status/}
id=${id%%[^0-9]*}

#echo "Grabbing ${nitter}/i/status/${id}"

# --retina doubles size. if used, set chop to 0x75, otherwise 0x50
shot-scraper -b firefox --retina -s '.main-thread' -h 2000 \
  "${nitter}/i/status/${id}" -o - |
  magick png:- -gravity north -chop 0x75 ${id}.png &&
  echo "${id}.png saved"
