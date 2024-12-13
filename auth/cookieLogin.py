#!/usr/bin/env python
# Basic Twitter login using cookies.json
from selenium import webdriver
from selenium.webdriver.firefox.service import Service as FirefoxService
from webdriver_manager.firefox import GeckoDriverManager
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.firefox_profile import FirefoxProfile
import json

url = 'https://x.com/i/api/' # load dummy page for faster login
twurl = 'https://x.com'

driver = webdriver.Firefox(service=FirefoxService(GeckoDriverManager().install()))
driver.get(url)

with open('cookies.json') as cookies_json:
    cookies = json.load(cookies_json)
    auth_token = cookies['auth_token']
    cookies_json.close()

driver.add_cookie({"name": "auth_token", "value": auth_token, "domain": ".x.com"})
driver.get(twurl)
#driver.refresh() # Refresh url to auth using cookies 

#driver.quit()
