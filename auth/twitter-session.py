#!/usr/bin/env python3
# Load a Twitter session using auth_token

from selenium import webdriver
from selenium.webdriver.firefox.service import Service as FirefoxService
from webdriver_manager.firefox import GeckoDriverManager
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.firefox_profile import FirefoxProfile
import sys
import os

try:
    arg1 = sys.argv[1]
except IndexError:
    print("Usage: " + os.path.basename(__file__) + " <auth_token>")
    sys.exit(1)

url = 'https://x.com/i/api/' # load dummy page for faster auth
twurl = 'https://x.com'

driver = webdriver.Firefox(service=FirefoxService(GeckoDriverManager().install()))
driver.get(url)
auth_token = sys.argv[1]
driver.add_cookie({"name": "auth_token", "value": auth_token, "domain": ".x.com"})
driver.get(twurl)
#driver.refresh() # Refresh url to auth using cookies 
#driver.quit()
