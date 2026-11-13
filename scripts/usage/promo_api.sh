#!/usr/bin/env bash
# Is the ProductCategory lookup failure specific to the Mindbody category, or every category?
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
ULT=$(q "SELECT Id FROM Product2 WHERE ProductCode = 'MB-ULT'" | jq -r '.[0].Id')
T=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
for X in '{"ProductCategory":"0ZGhm0000003Fk5GAE"}' '{"ProductCategory":"0ZGhm00000039AGGAY"}' '{"ProductCategory":"0ZGhm0000003FCDGA2"}' '{"Product":"01thm000000XXXXAAA"}' "{\"Product\":\"$ULT\",\"ProductCategory\":\"0ZGhm00000039AGGAY\"}"; do
  I=$(jq -nc --argjson x "$X" '{LineItem: "L1", Quantity: 1} + $x')
  B=$(jq -nc --arg t "$T" --argjson i "$I" '{cart: {SalesTransaction: [{CurrencyIsoCode: "USD", StartDate: $t, SalesTransactionItem: [$i]}]}}')
  echo "== $X"; echo "   $(rest POST /global-promotions-management/eligible-promotions "$B" | tr -d '\n' | head -c 600)"
done
echo "CATEGORY FIELDS $(q "SELECT Id, Name, Code, CatalogId, IsNavigational, NumberOfProducts FROM ProductCategory WHERE Id IN ('0ZGhm0000003Fk5GAE','0ZGhm00000039AGGAY','0ZGhm0000003FCDGA2')")"
echo "CATALOGS $(q "SELECT Id, Name, CatalogType, EffectiveStartDate, EffectiveEndDate FROM ProductCatalog")"
