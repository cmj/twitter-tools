#!/bin/bash
# grab the stats from a twitter user
# requires account, 2 parameters from header
# output: 
#  20240704-110910 tweets: 46561 friends: 650 followers: 188667122 likes: 58781

x_csrf_token=''
auth_token=''

####

user="elonmusk"
bearer_token='AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'
date=$(date +%Y%m%d-%H%M%S)
stats=$(curl -s "https://api.twitter.com/1.1/users/lookup.json?screen_name=${user//@/}" \
  -H "Authorization: Bearer ${bearer_token}" \
  -H "X-Csrf-Token: ${x_csrf_token}" \
  -H "Cookie: ct0=${x_csrf_token}; auth_token=${auth_token}" | \
  jq -r '.[] | "tweets: \(.statuses_count) friends: \(.friends_count) followers: \(.followers_count) likes: \(.favourites_count)"')

echo "${date} ${stats}"
#echo "${date} ${stats}" >> $file 

