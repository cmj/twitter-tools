#!/usr/bin/env python3
# returns oauth token for Twitter account
# append to Nitter sessions.jsonl

import requests
import json
import re
import sys


if len(sys.argv) != 3:
    print("Usage: python3 twitter_oauth.py <username> <password>")
    sys.exit(1)

username = sys.argv[1]
password = sys.argv[2]
#email=""

#proxies = {'http': 'http://127.0.0.1:8888', 'https': 'http://127.0.0.1:8888'}
proxies = None
#verify = "/tmp/mitm.crt"
verify = True

authorization_bearer = 'Bearer AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'
guest_token = requests.post("https://api.twitter.com/1.1/guest/activate.json",
                            headers={
                                'Authorization': authorization_bearer,
                                "User-Agent": "TwitterAndroid/10.21.0-release.0 (310210000-r-0) ONEPLUS+A3010/9"
                            }).json()['guest_token']

url_flow_1 = "https://api.twitter.com/1.1/onboarding/task.json?flow_name=login"
url_flow_2 = "https://api.twitter.com/1.1/onboarding/task.json"

# flow 1
data = {'': ''}
headers = {
    'Authorization': authorization_bearer,
    "Content-Type": "application/json",
    "User-Agent": "TwitterAndroid/10.21.0-release.0 (310210000-r-0) ONEPLUS+A3010/9 (OnePlus;ONEPLUS+A3010;OnePlus;OnePlus3;0;;1;2016)",
    "X-Twitter-API-Version": '5',
    "X-Twitter-Client": "TwitterAndroid",
    "X-Twitter-Client-Version": "10.21.0-release.0",
    "OS-Version": "28",
    "System-User-Agent": "Dalvik/2.1.0 (Linux; U; Android 9; ONEPLUS A3010 Build/PKQ1.181203.001)",
    "X-Twitter-Active-User": "yes",
    "X-Guest-Token": guest_token,
    "X-Twitter-Client-DeviceID": ""
}

r = requests.post(url_flow_1, proxies=proxies, verify=verify, headers=headers, data=json.dumps(data))
att = r.headers.get('att')
flow_token = json.loads(r.text)['flow_token']

# username
data = {"flow_token": flow_token ,"subtask_inputs":[{"subtask_id":"LoginEnterUserIdentifierSSO","settings_list":{"setting_responses":[{"key":"user_identifier","response_data":{"text_data":{"result":username}}}],"link":"next_link"}}]}

# include att
headers['att'] = att
r = requests.post(url_flow_2, proxies=proxies, verify=verify, headers=headers, data=json.dumps(data))
flow_token = json.loads(r.text)['flow_token']

# email check. haven't seen this needed yet
if (json.loads(r.text)['subtasks'][0]['subtask_id'] == "LoginEnterAlternateIdentifierSubtask"):
    data = {"flow_token": flow_token, "subtask_inputs":[{"subtask_id":"LoginEnterAlternateIdentifierSubtask","enter_text":{"text": email,"link":"next_link"}}]}
    headers = { 'att': att, 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:91.0) Gecko/20100101 Firefox/91.0', 'Referer': 'https://twitter.com/sw.js', 'X-Guest-Token': guest_token, 'Content-Type': 'application/json', 'Authorization':  authorization_bearer  }
    r = requests.post(url_flow_2, proxies=proxies, verify=verify, headers=headers, data=json.dumps(data))
    flow_token = json.loads(r.text)['flow_token']

# password
data = {"flow_token": flow_token ,"subtask_inputs":[{"subtask_id":"LoginEnterPassword","enter_password":{"password":password,"link":"next_link"}}]}
r = requests.post(url_flow_2, proxies=proxies, verify=verify, headers=headers, data=json.dumps(data))
flow_token = json.loads(r.text)['flow_token']
#user_id = json.loads(r.text)['subtasks'][0]['check_logged_in_account']['user_id']

token = json.loads(r.text)['subtasks'][0]['open_account']['oauth_token']
secret = json.loads(r.text)['subtasks'][0]['open_account']['oauth_token_secret']
account = {"oauth_token": token, "oauth_token_secret": secret}
print(json.dumps(account))
