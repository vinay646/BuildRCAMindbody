#!/usr/bin/env bash
# CHANGES the org: assign MB_Floor_Price to the admin user, Mindbody Floor Prices price book + entries, floor check on test lines
sf org assign permset --name MB_Floor_Price --target-org target 2>&1 | tail -3
python3 scripts/qa_build/floor_book.py
