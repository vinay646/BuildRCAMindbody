#!/usr/bin/env bash
# Replay eligible-promotions with context-tag shaped carts, with / without ProductCategory.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
CAT=0ZGhm0000003Fk5GAE
ULT=$(q "SELECT Id FROM Product2 WHERE ProductCode = 'MB-ULT'" | jq -r '.[0].Id')
ACC=$(q "SELECT Id FROM Account WHERE Name = 'Pulse Fitness Brands' LIMIT 1" | jq -r '.[0].Id')
PSM=$(q "SELECT ProductSellingModelId FROM ProductSellingModelOption WHERE Product2Id = '$ULT' LIMIT 1" | jq -r '.[0].ProductSellingModelId')
T=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
call() { echo "== $1"; echo "   $(rest POST /global-promotions-management/eligible-promotions "$2" | tr -d '\n' | head -c 1500)"; }
item() { jq -nc --arg p "$ULT" --arg psm "$PSM" --argjson extra "$1" '{LineItem: "L1", Product: $p, ProductSellingModel: $psm, Quantity: 1, ListPrice: 449, NetUnitPrice: 449} + $extra'; }
for SHAPE in node list; do
 for X in '{}' "{\"ProductCategory\":\"$CAT\"}" '{"ProductCategory":"Subscriptions"}'; do
  I=$(item "$X")
  if [ $SHAPE = node ]; then B=$(jq -nc --arg a "$ACC" --arg t "$T" --argjson i "$I" '{cart: {SalesTransaction: [{SalesTransaction: "Q1", Account: $a, CurrencyIsoCode: "USD", StartDate: $t, SalesTransactionItem: [$i]}]}}')
  else B=$(jq -nc --arg a "$ACC" --arg t "$T" --argjson i "$I" '{cart: {SalesTransaction: {SalesTransaction: "Q1", Account: $a, CurrencyIsoCode: "USD", StartDate: $t, SalesTransactionItem: [$i]}}}'); fi
  call "$SHAPE extra=$X" "$B"
 done
done
echo "CATEGORY SOQL as API user: $(q "SELECT Id, Name FROM ProductCategory WHERE Id = '$CAT'")"
echo "PCM category API: $(rest GET /connect/pcm/catalogs/0ZShm0000003JCbGAM/categories | tr -d '\n' | head -c 600)"
