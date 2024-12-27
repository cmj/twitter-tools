#!/usr/bin/python
import sys
import asyncio
from twikit import Client

search = ' '.join(sys.argv[1:])
limit = 4
client = Client(language='en-US') #, proxy='http://127.0.0.1:8888') # charles proxy
client.load_cookies('cookies.json')

async def main():
    tweets = await client.search_tweet(search, 'Latest', limit) # Latest, Top 
    for tweet in tweets:
        ts = tweet.created_at # _datetime
        text = tweet.full_text
        user = tweet.user.screen_name
        user_name = tweet.user.name
        replies = tweet.reply_count
        likes = tweet.favorite_count
        rt = tweet.retweet_count
        vcount = tweet.view_count
        views = vcount if vcount is not None else 0
        id = tweet.id
        print(("[" + str(ts) + "] @" + user
               + " (" + user_name + ")\n" + text 
               + "\n(↳ {:,}".format(replies)
               + " ⇅ {:,}".format(rt)
               + " ♥ {:,}".format(likes) 
               + " 🡕 {:,}".format(int(views)) 
               + ")\nhttps://x.com/_/status/" + id + "\n"))
asyncio.run(main())
