#!/usr/bin/env bash
# READ ONLY: in the debug logs of the last 20 minutes, did RepriceQuotesPST reprice inside the save, or fall back to the queued job?
set -uo pipefail
SINCE=$(date -u -d '-20 min' +%Y-%m-%dT%H:%M:%SZ)
inside=0; queued=0; jobs=0
for lid in $(sf data query --use-tooling-api --query "SELECT Id FROM ApexLog WHERE StartTime > $SINCE ORDER BY StartTime" --target-org target --json | jq -r '.result.records[].Id'); do
  body=$(sf api request rest "/services/data/v$ORG_API/tooling/sobjects/ApexLog/$lid/Body" --target-org target 2>/dev/null)
  echo "$body" | grep -q "RepriceQuotesPST.repriceQuotesPST" || { echo "$body" | grep -q "RepriceJob" && jobs=$((jobs+1)); continue; }
  if echo "$body" | grep -q "Immediate reprice not possible"; then
    queued=$((queued+1)); echo "QUEUED: $(echo "$body" | grep -o 'Immediate reprice not possible.*' | head -1 | cut -c1-300)"
  else
    inside=$((inside+1))
  fi
done
echo "reprice inside the save: $inside | fell back to queued job: $queued | queued job runs seen: $jobs"
