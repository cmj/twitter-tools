#!/usr/bin/env python3
# Load a Twitter session using auth_token

import os
import sys
import traceback

from selenium import webdriver
from selenium.webdriver.firefox.service import Service as FirefoxService

DUMMY_URL = 'https://x.com/i/api/'  # load dummy page for faster auth
TARGET_URL = 'https://x.com'

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {os.path.basename(__file__)} <auth_token>")
        sys.exit(1)

    auth_token = sys.argv[1]

    try:
        service = FirefoxService("/usr/local/bin/geckodriver", log_output=sys.stdout)
        driver = webdriver.Firefox(service=service)
    except Exception:
        traceback.print_exc()
        raise

    driver.get(DUMMY_URL)
    driver.add_cookie({"name": "auth_token", "value": auth_token, "domain": ".x.com"})
    driver.get(TARGET_URL)

    input("Session loaded. Press Enter to quit...")
    driver.quit()

if __name__ == "__main__":
    main()
