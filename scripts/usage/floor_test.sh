#!/usr/bin/env bash
# PRC-18: price Pulse quotes through the standard Place Sales Transaction API; the MB_Quote_Line_Floor_Price flow sets Floor Price.
#   Ultimate x2, 36 months, Annual          -> 371.85, floor 339, not below
#   Ultimate x2, 36 months, Annual, 20% off -> 297.48, floor 339, BELOW
#   Starter x1, 36 months, Monthly          -> floor 59
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
ACC=$(q "SELECT Id FROM Account WHERE Name = 'Pulse Fitness Brands' LIMIT 1" | jq -r '.[0].Id')
CON=$(q "SELECT Id FROM Contact WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id')
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name = 'North America & Asia (USD)'" | jq -r '.[0].Id')
LE=$(q "SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - US'" | jq -r '.[0].Id')
TODAY=$(date -u +%Y-%m-%d); END=$(date -u -d '+36 months -1 day' +%Y-%m-%d); STAMP=$(date -u +%m%d-%H%M)
echo "ACTIVE VERSION $(q "SELECT VersionNumber FROM ExpressionSetVersion WHERE ExpressionSet.ApiName = 'RLM_DefaultPricingProcedure' AND IsActive = true")"
for CASE in "MB-ULT|2|Annual|0" "MB-ULT|2|Annual|20" "MB-STR|1|Monthly|0"; do
  IFS='|' read -r CODE QTY FREQ DISC <<< "$CASE"
  PBE=$(q "SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = '$CODE' AND Pricebook2Id = '$PB' AND CurrencyIsoCode = 'USD' AND IsActive = true AND ProductSellingModel.Name = 'Term Monthly' LIMIT 1")
  PBEID=$(echo "$PBE" | jq -r '.[0].Id'); PROD=$(echo "$PBE" | jq -r '.[0].Product2Id')
  OPP=$(sf data create record --sobject Opportunity --values "Name='Floor $CODE $DISC $STAMP' AccountId=$ACC StageName=Prospecting CloseDate=$TODAY Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
  BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg prod "$PROD" --arg pbe "$PBEID" --arg d "$TODAY" --arg e "$END" --arg con "$CON" --arg le "$LE" \
    --argjson qty "$QTY" --arg freq "$FREQ" --argjson disc "$DISC" '{
    pricingPref: "System", catalogRatesPref: "Skip", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
    graph: {graphId: "floor", records: [
      {referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: "Floor test", OpportunityId: $opp, Pricebook2Id: $pb,
        BillToContactId: $con, StartDate: $d, RLM_TermMonths__c: 36, LegalEntityId: $le}},
      {referenceId: "l1", record: ({attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}", Product2Id: $prod,
        PricebookEntryId: $pbe, Quantity: $qty, StartDate: $d, EndDate: $e, PeriodBoundary: "Anniversary", BillingFrequency: $freq}
        + (if $disc > 0 then {Discount: $disc} else {} end))}]}}')
  echo "===== $CODE x$QTY $FREQ discount $DISC%"
  echo "place $(rest POST /connect/rev/sales-transaction/actions/place "$BODY" | jq -c '{isSuccess, errorResponse}')"
  sleep 10
  QUOTE=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' LIMIT 1" | jq -r '.[0].Id // empty')
  echo "LINE $(q "SELECT ListPrice, Discount, NetUnitPrice, MB_Floor_Price__c, MB_Below_Floor__c, CurrencyIsoCode FROM QuoteLineItem WHERE QuoteId = '$QUOTE'")"
done
