# returns oauth token for twitter account. can be used with low-traffic, private nitter instance
# key elements from https://unam.re/blog/developing-your-own-twitter-api

import requests
import json
import re

username=""
password=""
#email=""

#proxies = {'http': 'http://127.0.0.1:8888', 'https': 'http://127.0.0.1:8888'}
proxies = None
#verify = "/tmp/mitm.crt"
verify = True

authorization_bearer = 'Bearer AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3DRUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F'
guest_token = requests.post("https://api.twitter.com/1.1/guest/activate.json", headers={'Authorization': authorization_bearer}).json()['guest_token']

url_flow_1 = "https://twitter.com/i/api/1.1/onboarding/task.json?flow_name=login"
url_flow_2 = "https://twitter.com/i/api/1.1/onboarding/task.json"

# flow 1
data = {'': ''}
headers = { 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:91.0) Gecko/20100101 Firefox/91.0', 'Referer': 'https://twitter.com/sw.js', 'X-Guest-Token': guest_token, 'Content-Type': 'application/json', 'Authorization':  authorization_bearer  }
r = requests.post(url_flow_1, proxies=proxies, verify=verify, headers=headers, data=json.dumps(data))
att = r.headers.get('att')
flow_token = json.loads(r.text)['flow_token']

# flow 2
data = {"flow_token": flow_token ,"subtask_inputs":[{"subtask_id":"LoginEnterUserIdentifierSSO","settings_list":{"setting_responses":[{"key":"user_identifier","response_data":{"text_data":{"result":username}}}],"link":"next_link"}}]}
# include att
headers = { 'att': att, 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:91.0) Gecko/20100101 Firefox/91.0', 'Referer': 'https://twitter.com/sw.js', 'X-Guest-Token': guest_token, 'Content-Type': 'application/json', 'Authorization':  authorization_bearer  }
r = requests.post(url_flow_2, proxies=proxies, verify=verify, headers=headers, data=json.dumps(data))
flow_token = json.loads(r.text)['flow_token']

# email check. haven't seen this needed yet
if (json.loads(r.text)['subtasks'][0]['subtask_id'] == "LoginEnterAlternateIdentifierSubtask"):
    data = {"flow_token": flow_token, "subtask_inputs":[{"subtask_id":"LoginEnterAlternateIdentifierSubtask","enter_text":{"text": email,"link":"next_link"}}]}
    headers = { 'att': att, 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:91.0) Gecko/20100101 Firefox/91.0', 'Referer': 'https://twitter.com/sw.js', 'X-Guest-Token': guest_token, 'Content-Type': 'application/json', 'Authorization':  authorization_bearer  }
    r = requests.post(url_flow_2, proxies=proxies, verify=verify, headers=headers, data=json.dumps(data))
    flow_token = json.loads(r.text)['flow_token']

# flow 3
data = {"flow_token": flow_token ,"subtask_inputs":[{"subtask_id":"LoginEnterPassword","enter_password":{"password":password,"link":"next_link"}}]}
r = requests.post(url_flow_2, proxies=proxies, verify=verify, headers=headers, data=json.dumps(data))
flow_token = json.loads(r.text)['flow_token']
#user_id = json.loads(r.text)['subtasks'][0]['check_logged_in_account']['user_id']

# flow 4 (final)
data = {"flow_token":flow_token,"subtask_inputs":[{"subtask_id":"AccountDuplicationCheck","check_logged_in_account":{"link":"AccountDuplicationCheck_false"}}]}
r = requests.post(url_flow_2, proxies=proxies, verify=verify, headers=headers, data=json.dumps(data))

token = json.loads(r.text)['subtasks'][0]['open_account']['oauth_token']
secret = json.loads(r.text)['subtasks'][0]['open_account']['oauth_token_secret']
account = {"oauth_token": token, "oauth_token_secret": secret}
print(json.dumps(account))
