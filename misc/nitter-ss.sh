#!/usr/bin/env bash
# take a screenshot of a tweet
# requires: shot-scraper

# set nitter instance, see: https://github.com/zedeus/nitter/wiki/Instances
#nitter="https://nitter.net"
nitter="http://nitter.local"  

url="$1"

if [[ -z "$url" ]]; then
  echo -e "Screenshot a tweet from Nitter\nUsage: $0 <url or id>"
  exit 1
fi

id=${url#*/status/}
id=${id%%[^0-9]*}

# shot-scraper uses playwright: chromium (default), firefox, and webkit. set with -b option
# --retina doubles size.
shot-scraper \
  -b firefox \
  --retina \
  --javascript '
    if (document.querySelector(".before-tweet")) {
      document.querySelector(".main-thread").id = "shot-target";
    } else {
      document.querySelector("nav").remove();
      document.querySelector(".main-tweet .timeline-item").id = "shot-target";
    }
  ' \
  -s '#shot-target' \
  -h 2000 \
  "${nitter}/i/status/${id}" -o "${id}.png"
