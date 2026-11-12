#!/usr/bin/env bash
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
for o in Quote QuoteLineItem Order OrderItem Account; do
  echo "$o legal/treatment fields: $(sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.name|test("LegalEntity|BillingTreatment|BillingPolicy";"i")) | {name, updateable, ref: .referenceTo}]')"
done
echo "LEGAL ENTITIES $(q "SELECT Id, Name, Status FROM LegalEntity")"
echo "QB QUOTE $(q "SELECT Id, QuoteNumber, LegalEntityId FROM Quote WHERE Name LIKE 'Usage Test%' ORDER BY CreatedDate DESC LIMIT 2")"
./scripts/usage/pricing_place.sh
