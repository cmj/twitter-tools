#!/usr/bin/env python
# Login to Twitter using only auth_token
from selenium import webdriver
from selenium.webdriver.firefox.service import Service as FirefoxService
from webdriver_manager.firefox import GeckoDriverManager
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.firefox_profile import FirefoxProfile
import time
import os

print("Twitter Login")
auth_token = input("auth_token: ")
print("Started. Console does not auto-close. Please close it manually.")

options=Options()
url = 'https://x.com/'
driver = webdriver.Firefox(service=FirefoxService(GeckoDriverManager().install()), options=options)
driver.get(url)
driver.add_cookie({"name": "auth_token", "value": auth_token, "domain": ".x.com"})
driver.get('https://x.com/settings/account')

while True:
    time.sleep(1)
