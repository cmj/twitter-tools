#!/usr/bin/env python3
# Load a Twitter session using auth_token (zendriver)

import asyncio
import sys

import zendriver as zd
from zendriver.cdp.network import CookieParam

async def main(auth_token):
    browser = await zd.start()
    await browser.cookies.set_all([CookieParam(name="auth_token", value=auth_token, domain=".x.com")])
    await browser.get("https://x.com")
    input("Session loaded. Press Enter to quit...")
    await browser.stop()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} <auth_token>")
    asyncio.run(main(sys.argv[1]))
