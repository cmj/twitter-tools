#!/bin/bash
# return timestamp of Twitter id/post

# Bitwise left shift of 22, removing sequence number, data center id, and
# machine id, leaving only the milliseconds epoch time of transaction 

id=$1
d=$((($id>>22)+1288834974657)); LC_TIME=en_GB date -d @${d:: -3} +'%a %b %d, %Y %T UTC' -u
