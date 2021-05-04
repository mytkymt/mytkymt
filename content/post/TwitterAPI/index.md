---
Title: "Delete old tweets when the total number of tweets is over three"
DATE: 2021-05-04
Tag: Haptics
---
I made a simple python-based web app.

The app automatically deletes my tweets when the total number of tweets is more than three.

I used following items.
 - twitter API
 - python 3 with tweepy (you may need to install)
 - pythonanywhere (simple and easy-to-use web server)

For details of those APIs and services, please visit other sites.

The source code is open below.
I referred <a src=https://tech-lab.sios.jp/archives/21400> this web site </a>.

```python
import tweepy
import time

consumer_key ="YOUR_API_KEY"
consumer_secret ="YOUR_API_SECRET"
access_token="YOUR_ACCESS_TOKEN"
access_token_secret ="YOUR_ACCESS_TOKEN_SECRET"

auth = tweepy.OAuthHandler(consumer_key, consumer_secret)
auth.set_access_token(access_token, access_token_secret)
api = tweepy.API(auth)

while True:
  tweets = api.user_timeline(count=200, page=1)
  num = 0
  for tweet in tweets:
    num += 1
  while num > 3:
    api.destroy_status(tweets[num-1].id)
    num = num -1
  time.sleep(10)


```