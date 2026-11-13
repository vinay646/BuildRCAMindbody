#!/usr/bin/env bash
# Diagnose the Promotions tab error: settings, rule library, then call the promotion APIs directly to get the real message.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
echo "RULE LIBRARY $(q "SELECT FIELDS(STANDARD) FROM RuleLibrary LIMIT 5" | jq -c '[.[]? | with_entries(select(.value != null and (.key|test("Created|LastModified|System|IsDeleted|LastViewed|LastReferenced|Owner")|not)))]')"
echo "RULE LIBRARY VERSIONS $(q "SELECT FIELDS(STANDARD) FROM RuleLibraryVersion LIMIT 5" | jq -c '[.[]? | with_entries(select(.value != null and (.key|test("Created|LastModified|System|IsDeleted|LastViewed|LastReferenced|Owner")|not)))]')"
echo "SETTINGS"
rm -rf rs; mkdir rs; sf project retrieve start --api-version "$ORG_API" --metadata "Settings:RevenueManagement" --metadata "Settings:GlobalPromotionsManagement" --target-org target --target-metadata-dir rs --unzip --wait 10 --json > rs.json 2>&1 || true
for f in $(find rs -type f -name '*.settings*'); do echo "-- $f"; sed -e 's/^[[:space:]]*//' "$f" | tr -d '\n' | grep -o -i '<[a-z]*promo[^<]*<[^>]*>\|<[a-z]*rule[^<]*<[^>]*>' ; echo; done
QUOTE=$(q "SELECT Id FROM Quote WHERE Opportunity.Account.Name = 'Pulse Fitness Brands' ORDER BY LastModifiedDate DESC LIMIT 1" | jq -r '.[0].Id')
echo "QUOTE $QUOTE $(q "SELECT QuoteNumber, Name, CalculationStatus, LegalEntityId, RLM_TermMonths__c FROM Quote WHERE Id = '$QUOTE'")"
echo "LINES $(q "SELECT Id, Product2.ProductCode, BillingFrequency, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '$QUOTE'")"
LINE=$(q "SELECT Id FROM QuoteLineItem WHERE QuoteId = '$QUOTE' AND Product2.ProductCode = 'MB-ULT' LIMIT 1" | jq -r '.[0].Id // empty')
PROMO=$(q "SELECT Id FROM Promotion WHERE Name = 'SWITCH50'" | jq -r '.[0].Id')
echo "LINE $LINE PROMO $PROMO"
echo "PROMOTION OBJECTS $(rest GET /sobjects | jq -c '[.sobjects[] | select(.name|test("Promotion";"i")) | select(.name|test("Feed|History|Share|ChangeEvent")|not) | .name]')"
for p in /connect/global-promotions-management /global-promotions-management /connect/revenue-management/promotions /connect/rev/promotions \
         /connect/global-promotions-management/eligible-promotions /global-promotions-management/eligible-promotions \
         /connect/promotions /connect/rule-library /connect/rev/sales-transaction/promotions; do
  echo "GET $p => $(rest GET $p | tr -d '\n' | head -c 400)"
  echo "POST $p => $(rest POST $p '{}' | tr -d '\n' | head -c 400)"
done
echo "STANDARD ACTIONS $(rest GET /actions/standard | jq -c '[.actions[]? | select(.name|test("romot|ule";"i")) | .name]')"
echo "RECALC via place (Force pricing) on $QUOTE"
BODY=$(jq -nc --arg qid "$QUOTE" '{pricingPref: "Force", catalogRatesPref: "Skip", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
  graph: {graphId: "recalc", records: [{referenceId: "q1", record: {attributes: {type: "Quote", method: "PATCH", id: $qid}}}]}}')
rest POST /connect/rev/sales-transaction/actions/place "$BODY" | jq -c '.' | head -c 1500; echo
sleep 8
echo "AFTER $(q "SELECT CalculationStatus FROM Quote WHERE Id = '$QUOTE'") $(q "SELECT Product2.ProductCode, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '$QUOTE'")"
echo "RECENT LOGS $(q "SELECT Id, Operation, Status, StartTime FROM ApexLog ORDER BY StartTime DESC LIMIT 5")"
