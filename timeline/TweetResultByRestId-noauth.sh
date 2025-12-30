#!/bin/bash
# No auth Tweet by ID
#

id=$1

usage() { echo "$0 <tweet_id>"; exit 1; }; [ "$#" -ne 1 ] && usage

bearer_token='AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
guest_token=$(curl -s -XPOST -H "Authorization: Bearer ${bearer_token}" "https://api.twitter.com/1.1/guest/activate.json" | jq -r '.guest_token')
variables='{"withSafetyModeUserFields":true,"includePromotedContent":true,"withQuickPromoteEligibilityTweetFields":true,"withVoice":true,"withV2Timeline":true,"withDownvotePerspective":false,"withBirdwatchNotes":true,"withCommunity":true,"withSuperFollowsUserFields":true,"withReactionsMetadata":false,"withReactionsPerspective":false,"withSuperFollowsTweetFields":true,"isMetatagsQuery":false,"withReplays":true,"withClientEventToken":false,"withAttachments":true,"withConversationQueryHighlights":true,"withMessageQueryHighlights":true,"withMessages":true,"tweetId":"'"${id}"'"}'
features='{"creator_subscriptions_tweet_preview_api_enabled":true,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"tweetypie_unmention_optimization_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"tweet_with_visibility_results_prefer_gql_media_interstitial_enabled":true,"rweb_video_timestamps_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_enhance_cards_enabled":false}'
fieldToggles='{"withArticleRichContentState":true,"withArticlePlainText":true}'


curl -sG "https://twitter.com/i/api/graphql/7xflPyRiUxGVbJd4uWmbfg/TweetResultByRestId" \
  -H "Authorization: Bearer ${bearer_token}" \
  -H "X-Guest-Token: ${guest_token}" \
  --data-urlencode "variables=${variables}" \
  --data-urlencode "features=${features}" \
  --data-urlencode "fieldToggles=${fieldToggles}" |
  jq -c #| tee "TweetResultByRestId-$id-$EPOCHSECONDS"
