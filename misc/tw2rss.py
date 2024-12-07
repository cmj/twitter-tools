#!/usr/bin/python3
"""
GGI script - Generate RSS feed from twitter user
Requires valid Twitter account
query parameters:
  u = username
  l = limit of items
  r = for all tweets and replies
defaults to @nasa, 10 items and no replies
(replies query may have a heavier rate-limit) 
Tweets from @NWS, 10 items: http://host/cgi-bin/tw2rss?u=NWS
20 items from @elonmusk with replies: http://host/cgi-bin/tw2rss?u=elonmusk&l=20&r=1
"""

import json
import requests
import argparse
import datetime
import time
import re
import warnings

with warnings.catch_warnings():
    warnings.filterwarnings("ignore",category=DeprecationWarning)
    import cgi

# requires both:
X_CSRF_TOKEN = 'XXXXXXXXXX'
COOKIE = 'ct0=XXXXXXXXXX; auth_token=XXXXXXXXXX'

# change to nitter instance
#TWEET_URL = 'http://shitter'
TWEET_URL = 'https://twitter.com'

###
AUTHORIZATION_TOKEN = 'AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'
FEATURES_USER = '{"hidden_profile_likes_enabled":false,"hidden_profile_subscriptions_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"subscriptions_verification_info_is_identity_verified_enabled":false,"subscriptions_verification_info_verified_since_enabled":true,"highlights_tweets_tab_ui_enabled":true,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true}'
FEATURES_TWEETS = '{"android_graphql_skip_api_media_color_palette":false,"blue_business_profile_image_shape_enabled":false,"creator_subscriptions_subscription_count_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"freedom_of_speech_not_reach_fetch_enabled":false,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":false,"hidden_profile_likes_enabled":false,"highlights_tweets_tab_ui_enabled":false,"interactive_text_enabled":false,"longform_notetweets_consumption_enabled":true,"longform_notetweets_inline_media_enabled":false,"longform_notetweets_richtext_consumption_enabled":true,"longform_notetweets_rich_text_read_enabled":false,"responsive_web_edit_tweet_api_enabled":false,"responsive_web_enhance_cards_enabled":false,"responsive_web_graphql_exclude_directive_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":false,"responsive_web_media_download_video_enabled":false,"responsive_web_text_conversations_enabled":false,"responsive_web_twitter_article_tweet_consumption_enabled":false,"responsive_web_twitter_blue_verified_badge_is_enabled":true,"rweb_lists_timeline_redesign_enabled":true,"spaces_2022_h2_clipping":true,"spaces_2022_h2_spaces_communities":true,"standardized_nudges_misinfo":false,"subscriptions_verification_info_enabled":true,"subscriptions_verification_info_reason_enabled":true,"subscriptions_verification_info_verified_since_enabled":true,"super_follow_badge_privacy_enabled":false,"super_follow_exclusive_tweet_notifications_enabled":false,"super_follow_tweet_api_enabled":false,"super_follow_user_api_enabled":false,"tweet_awards_web_tipping_enabled":false,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":false,"tweetypie_unmention_optimization_enabled":false,"unified_cards_ad_metadata_container_dynamic_card_content_query_enabled":false,"verified_phone_label_enabled":false,"vibe_api_enabled":false,"view_counts_everywhere_api_enabled":false,"rweb_video_timestamps_enabled":false,"c9s_tweet_anatomy_moderator_badge_enabled":false}'
HEADERS = {
        'authorization': 'Bearer %s' % AUTHORIZATION_TOKEN,
        'x-csrf-token': X_CSRF_TOKEN,
        'cookie': COOKIE
}

GET_USER_URL = 'https://twitter.com/i/api/graphql/SAMkL5y_N9pmahSw8yy6gw/UserByScreenName'
GET_TWEETS_URL = 'https://twitter.com/i/api/graphql/XicnWRbyQ3WgVY__VataBQ/UserTweets'
GET_TWEETS_AND_REPLIES_URL = 'https://twitter.com/i/api/graphql/-gxtzCQbBPmOwxnY-SbiHQ/UserTweetsAndReplies'

FIELDNAMES = ['id', 'tweet_url', 'name', 'user_id', 'username', 'published_at', 'content', 'views_count', 'retweet_count', 'likes', 'quote_count', 'reply_count', 'bookmarks_count', 'medias']

class TwitterScraper:

    def __init__(self, username):
        self.HEADERS = HEADERS
        assert username
        self.username = username

    def get_user(self):
        arg = {"screen_name": self.username, "withSafetyModeUserFields": True}
        
        params = {
            'variables': json.dumps(arg),
            'features': FEATURES_USER,
        }
        
        response = requests.get(
            GET_USER_URL,
            params=params, 
            headers=self.HEADERS
        )

        try: 
            json_response = response.json()
        except requests.exceptions.JSONDecodeError: 
            print(response.status_code)
            print(response.text)
            raise

        result = json_response["data"]["user"]["result"]
        legacy = result["legacy"]

        return {
            "id": result["rest_id"],
            "username": legacy["screen_name"],
            "full_name": legacy["name"]
        }

    def tweet_parser(
            self,
            user_id, 
            full_name, 
            rest_id, 
            item_result, 
            legacy
        ):

        medias = legacy["entities"].get("media")
        medias = ", ".join(["%s (%s)" % (d["media_url_https"], d['type']) for d in medias]) if medias else ""
        urls = legacy["entities"].get("urls")
        urls = ", ".join([x["expanded_url"] for x in urls]) if urls else ""

        # Customize feed elements. Some may not be suited for RSS.
        return {
            "id": rest_id,
            "tweet_url": f"{TWEET_URL}/{self.username}/status/{rest_id}",
            "name": full_name,
            "user_id": user_id,
            "username": self.username,
            "published_at": legacy.get("created_at"),
            "content": legacy.get("full_text"),
            "urls": urls,
            "views_count": item_result.get("views", {}).get("count"),
            "retweet_count": legacy.get("retweet_count"),
            "likes": legacy.get("favorite_count"),
            "quote_count": legacy.get("quote_count"),
            "reply_count": legacy.get("reply_count"),
            "bookmarks_count": legacy.get("bookmark_count"),
            "medias": medias
        }

    def iter_tweets(self, replies, limit):
        _user = self.get_user()
        full_name = _user.get("full_name")
        user_id = _user.get("id")
        if not user_id:
            print("/!\\ error: no user id found")
            raise NotImplementedError
        cursor = None
        _tweets = []

        while True:
            var = {
                "userId": user_id, 
                "count": limit, 
                "cursor": cursor, 
                "includePromotedContent": False,
                "withQuickPromoteEligibilityTweetFields": True, 
                "withVoice": True,
                "withV2Timeline": True
            }

            params = {
                'variables': json.dumps(var),
                'features': FEATURES_TWEETS,
            }

            if replies:
                get_url = GET_TWEETS_AND_REPLIES_URL
            else:
                get_url = GET_TWEETS_URL

            response = requests.get(
                get_url,
                params=params,
                headers=self.HEADERS
            )

            json_response = response.json()
            # XXX
            #print(json.dumps(json_response))
            result = response.json()['data']['user']['result']
            timeline = result["timeline_v2"]["timeline"]["instructions"]
            entries = [x["entries"] for x in timeline if x["type"] == "TimelineAddEntries"]
            entries = entries[0] if entries else []

            for entry in entries:
                content = entry["content"]
                entry_type = content["entryType"]
                if entry['entryId'].startswith('tweet'):
                    item_result = content['itemContent']['tweet_results']['result']
                    legacy = item_result["legacy"]
                    tweet_id = content["itemContent"]["tweet_results"]["result"]["rest_id"]
                    
                    tweet_data = self.tweet_parser(user_id, full_name, tweet_id, item_result, legacy)
                    _tweets.append(tweet_data)
                
                if entry['entryId'].startswith('profile-conversation'):
                    threads = [content["items"]]
                    threads = threads[0] if threads else []
                    for thread in threads:
                        thread_result = thread['itemContent']['tweet_results']['result']
                        legacy = thread_result["legacy"]
                        tweet_id = thread["item"]["itemContent"]["tweet_results"]["result"]["rest_id"]
                        if tweet_id:
                            tweet_data = self.tweet_parser(user_id, full_name, tweet_id, item_result, legacy)
                            _tweets.append(tweet_data)

                if entry_type == "TimelineTimelineCursor" and content.get("cursorType") == "Bottom":
                    cursor = content.get("value")


                if len(_tweets) >= limit:
                    break

            if len(_tweets) >= limit or cursor is None or len(entries) == 2:
                break

        return _tweets

    def generate_rss(self, username, tweets=[]):
        
        rss = """\
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0">

<channel>
<title>{} - RSS Feed</title>
<link>https://twitter.com/{}</link>
<description>Twitter Feed for @{}</description>
""".format(username, username, username)
        # XXX after sorting, we trim last 7-10 items out of 20 requested 
        # from twitter for a more consistant feed layout
        tweets = sorted(tweets, key=lambda x: x['id'], reverse=True)
        limit_trimmed = 10
        for t in tweets[:limit_trimmed]: 
            rss += """\
<item>
    <title>{}</title>
    <author>@{}</author>
    <description>{}</description>
    <link>{}</link>
    <pubDate>{}</pubDate>
</item>
""".format(
        f"{t['content']} {t['medias']} {t['urls']}".strip(),
        username,        
        f"{t['content']} {t['medias']} {t['urls']}".strip(),
        f"{t['tweet_url']}",
        f"{t['published_at']}"
    )
        rss += "</channel>\n</rss>"
        print("Content-type: application/rss+xml")
        print("Cache-control: public, max-age=4000")
        print("Access-Control-Allow-Origin: *\n")
        print(rss)

def main():
    form = cgi.FieldStorage()
    username = "nasa"
    replies = None
    limit = 20
    if "u" in form:
      username = form["u"].value
    if "r" in form:
      replies = True
    if "l" in form:
      limit = int(form["l"].value)

    assert all([username, limit])

    twitter_scraper = TwitterScraper(username)
    tweets = twitter_scraper.iter_tweets(replies, limit=limit)
    assert tweets
    twitter_scraper.generate_rss(username, tweets)

if __name__ == '__main__':
    main()
