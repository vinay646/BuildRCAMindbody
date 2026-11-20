#!/usr/bin/env bash
# READ ONLY: full GPM promotion details of NewPromo and TodayOffer; ramp trigger source.
set -uo pipefail
API="/services/data/v$ORG_API"
for id in 0c8hm0000000uQPAAY 0c8hm0000000uS1AAI; do echo "== $id"; sf api request rest "$API/global-promotions-management/promotions/$id" --target-org target 2>&1; echo; done
echo "== ramp triggers / classes"
sf data query --use-tooling-api --query "SELECT Name, TableEnumOrId, Status FROM ApexTrigger WHERE Name LIKE '%Ramp%'" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)]'
sf data query --use-tooling-api --query "SELECT Name, Body FROM ApexTrigger WHERE Name = 'RLM_QuoteLineItemRampTrigger'" --target-org target --json | jq -r '.result.records[0].Body // "none"' | head -60
sf data query --use-tooling-api --query "SELECT Name FROM ApexClass WHERE Name LIKE '%Ramp%'" --target-org target --json | jq -c '[.result.records[]?.Name]'
