#!/bin/bash
# pip install pysparklines
# example output: https://i.imgur.com/2y0eLPk.png

cols=$(tput cols)
d0=$(date -Is -d '-1 day')
d1=$(date -Is)

clear

echo -e "\n@elonmusk combined twitter activity (likes+tweets) every 5min\n"
paste <(tail -n+2 twitter.dat | cut -d\  -f3,9) <(head -n-1 twitter.dat | cut -d\  -f3,9) |
  while read tw_1 li_1 tw_0 li_0; do
    echo $(($li_1-$li_0+$tw_1-$tw_0))
  done |
  tail -$(($cols-3)) |
  sparkline -r20 --min=0 --max=20 | 
  tac | 
  cat -n | 
  sed 's/\t/ /;s/^    //' | 
  tac |
  lolcat -F .2 -p 1000 -S 5 

mark=$(($cols/6+1))
markers=$(for((i=1;i<=$mark;i++)); do printf "     |"; ((x++)); done | sed 's/  |$/|/')

#tput cup $(tput lines) $[$(tput cols)-$cols]; 
echo "${markers: -$cols}"
ts=$(tail -200 twitter.dat | 
  sed -En 's/.*-([0-9]{2})([0-9]{2}).*/\1:\2 /p' | 
  tac | 
  sed '1 i\foo' | # insert dummy line 
  awk 'NR % 6 == 0' | 
  tac | 
  tr -d '\n' | 
  sed 's/$/T/')
echo "${ts: -$cols}"
