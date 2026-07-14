#!/usr/bin/env python3
# Tool to merge all csv files created by timeline_scrape.py 
import csv
import glob
import os
import sys

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <screen_name>")
    print(f"Example: {sys.argv[0]} nasa")
    sys.exit(1)

screen_name = sys.argv[1]

pattern = f"{screen_name}-*.csv"
# this will include the master.csv
#files = sorted(glob.glob(pattern))
files = sorted(
    f for f in glob.glob(pattern)
    if not f.endswith("-master.csv")
)

if not files:
    print(f"No files found matching '{pattern}'")
    sys.exit(1)

rows = {}

for fn in files:
    print(f"Reading {fn}")
    with open(fn, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows[row["Id"]] = row   # last occurrence wins

outfile = f"{screen_name}-master.csv"

fieldnames = [
    "Id",
    "Date",
    "Text",
    "Replies",
    "ReTweets",
    "Likes",
    "Views",
    "Source",
    "Birdwatch",
    "ConversationId",
    "Url",
]

with open(outfile, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for _, row in sorted(rows.items(), key=lambda item: int(item[0])):
        writer.writerow(row)

print(f"\nRead {len(files)} files.")
print(f"Wrote {len(rows)} unique tweets to {outfile}")
