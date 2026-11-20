#!/usr/bin/env bash
# READ ONLY: which APIs exist to create rule-library promotions and ramp (stepped) pricing.
set -uo pipefail
API="/services/data/v$ORG_API"
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1 | tr -d '\n' | head -c ${4:-700}; echo; }
echo "== standard actions (ramp / promotion / coupon / segment)"
sf api request rest "$API/actions/standard" --target-org target | jq -c '[.actions[]? | select(.name|test("amp|romo|oupon|egment|ule";"i")) | .name]'
echo "== sobjects (rule / ramp / segment)"
sf api request rest "$API/sobjects" --target-org target | jq -c '[.sobjects[] | select(.name|test("^Rule|RuleLib|Ramp|Segment|PromotionRule|Decision";"i")) | .name]'
echo "== GPM endpoints"
for p in /global-promotions-management/promotions /connect/global-promotions-management/promotions /global-promotions-management/promotions/0c8hm0000000uQPAAY /connect/loyalty/promotions; do echo "-- GET $p"; rest GET "$p"; done
echo "-- POST /global-promotions-management/promotions (empty body, to read the required fields)"; rest POST /global-promotions-management/promotions '{}' 1500
echo "== rule library and its versions / rules"
sf data query --query "SELECT Id, DeveloperName, MasterLabel, UsageType FROM RuleLibrary" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)]'
for o in RuleLibraryVersion RuleLibraryRule ExpressionSetDefinition; do echo "   $o: $(sf data query --query "SELECT FIELDS(STANDARD) FROM $o LIMIT 5" --target-org target --json | jq -c '[.result.records[]? | with_entries(select(.value != null and (.key|test("attributes|Created|LastModified|System|IsDeleted|Owner")|not)))] // .message' | head -c 900)"; done
echo "== ramp API probes"
for p in /connect/revenue-management/sales-transaction-contexts /connect/rev/sales-transaction/actions/ramp-deal-create /connect/revenue/transaction-management/ramp-deal/actions/create; do echo "-- POST $p"; rest POST "$p" '{}'; done
echo "== QuoteLineItem ramp fields"
sf api request rest "$API/sobjects/QuoteLineItem/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Ramp|Segment";"i")) | {n: .name, t: .type, c: .createable, v: [.picklistValues[]?.value]}]'
