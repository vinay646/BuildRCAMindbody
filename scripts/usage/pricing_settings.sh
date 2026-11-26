#!/usr/bin/env bash
# Read-only: lists the org's Settings metadata related to pricing / revenue / quotes and prints their flags (retrieved to a temp folder, nothing deployed)
NAMES=$(sf org list metadata --metadata-type Settings --target-org target --json 2>/dev/null | jq -r '.result[].fullName' | grep -i 'pric\|revenue\|quote\|sales\|industr\|order' | tr '\n' ' ')
echo "SETTINGS: $NAMES"
T=$(mktemp -d); cd $T; sf project generate --name p >/dev/null 2>&1; cd p
for n in $NAMES; do sf project retrieve start --metadata "Settings:$n" --target-org target --json >/dev/null 2>&1; done
for f in $(find . -name '*.settings-meta.xml'); do echo "== $(basename $f)"; grep -o '<[a-zA-Z]*>\(true\|false\)<' $f | sed 's/<\([a-zA-Z]*\)>\(true\|false\)</\1=\2/' | tr '\n' ' '; echo; done
