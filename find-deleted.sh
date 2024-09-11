#!/bin/bash
# Fast method to check from a list of tweet ids if a tweet has been deleted
# under 10 seconds per 1000 tweets

# We use a HEAD to check response size, if its content is less than 500 bytes,
#   it's been deleted

file=ids.out # file with list of IDs
#out=$(cat $file)
out=$(tail -1000 $file) # be reasonable, however there is no limit

jobs=100 # parallel jobs

lmao() {
  id=$1 
    curl -sI "https://cdn.syndication.twimg.com/tweet-result?id=${id}&lang=en&token=0" | 
      sed -En 's/^content-length: (.*)\r/\1/p' | 
      while read l; do 
        if [ "$l" -lt 500 ]; then 
            echo $id is DELETED
          else 
            echo $id
        fi
      done | tee $(date +%Y%m%d-%H%M%S)-findings.out
}

export -f lmao

parallel -j$jobs lmao {} ::: $out 

