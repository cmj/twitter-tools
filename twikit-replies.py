import asyncio
from twikit import Client

client = Client('en-US')

client.load_cookies('cookies.json')

# example https://x.com/NASA/status/1872664002058228008
tweet_id = 1872664002058228008

async def tweet_child(tweet_id):
  get_replies = await client.get_tweet_by_id(tweet_id)
  replies = get_replies.replies
  for reply in replies:
    screen_name = reply.user.screen_name
    text = reply.full_text
    print("@" +screen_name + " - " + text)

asyncio.run(tweet_child(tweet_id))
