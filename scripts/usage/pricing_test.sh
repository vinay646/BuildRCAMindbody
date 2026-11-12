#!/usr/bin/env bash
# P02 pricing test: Pulse Fitness Brands, Ultimate x2, 36 months, Annual -> expect 499 -> 449.10 -> 404.19 -> 371.85.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '.result.records // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
echo "sync pricing data: $(rest GET /connect/core-pricing/sync/syncData | tr -d "\n ")"; sleep 20
ACC=$(q "SELECT Id FROM Account WHERE Name = 'Pulse Fitness Brands' LIMIT 1" | jq -r '.[0].Id')
CON=$(q "SELECT Id FROM Contact WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id // empty')
[ -z "$CON" ] && CON=$(sf data create record --sobject Contact --values "FirstName=Pricing LastName=Tester Email=pricing.tester@example.com AccountId=$ACC" --target-org target --json | jq -r '.result.id')
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name = 'North America & Asia (USD)'" | jq -r '.[0].Id')
PBE=$(q "SELECT Id, Product2Id, UnitPrice, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ULT' AND Pricebook2Id = '$PB' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1")
echo "account=$ACC contact=$CON pricebook=$PB pbe=$PBE"
PBEID=$(echo "$PBE" | jq -r '.[0].Id'); PROD=$(echo "$PBE" | jq -r '.[0].Product2Id')
STAMP=$(date -u +%m%d-%H%M); TODAY=$(date -u +%Y-%m-%d); END=$(date -u -d '+36 months -1 day' +%Y-%m-%d)
OPP=$(sf data create record --sobject Opportunity --values "Name='P02 Pricing Test $STAMP' AccountId=$ACC StageName=Prospecting CloseDate=$TODAY Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id // .message')
echo "opportunity=$OPP"
QUOTE=$(sf data create record --sobject Quote --values "Name='P02 Pricing Test' OpportunityId=$OPP Pricebook2Id=$PB BillToContactId=$CON StartDate=$TODAY RLM_TermMonths__c=36" --target-org target --json | jq -r '.result.id // .message')
echo "quote=$QUOTE"
L=$(sf data create record --sobject QuoteLineItem --values "QuoteId=$QUOTE Product2Id=$PROD PricebookEntryId=$PBEID Quantity=2 UnitPrice=499 StartDate=$TODAY EndDate=$END PeriodBoundary=Anniversary BillingFrequency=Monthly" --target-org target --json); echo "$L" | jq -c '{status, id: .result.id, message}'
LID0=$(echo "$L" | jq -r '.result.id')
echo "set SubscriptionTerm=36: $(sf data update record --sobject QuoteLineItem --record-id "$LID0" --values "SubscriptionTerm=36" --target-org target --json | jq -c '{status, message}')"
echo "LINE SAVED $(q "SELECT BillingFrequency, Quantity, SubscriptionTerm, Volume_Location_Count__c, Billing_Period_Months__c FROM QuoteLineItem WHERE QuoteId = '$QUOTE'")"
LID=$(q "SELECT Id FROM QuoteLineItem WHERE QuoteId = '$QUOTE' LIMIT 1" | jq -r '.[0].Id')
show() { echo "  LINE $(q "SELECT BillingFrequency, Quantity, SubscriptionTerm, Volume_Location_Count__c, Billing_Period_Months__c, ListPrice, UnitPrice, NetUnitPrice, TotalPrice FROM QuoteLineItem WHERE Id = '$LID'")"; echo "  QUOTE $(q "SELECT CalculationStatus, TotalPrice FROM Quote WHERE Id = '$QUOTE'")"; }
place() { local line="$1"; RB=$(jq -nc --arg id "$QUOTE" --arg lid "$LID" --argjson line "$line" '{pricingPref: "Force", catalogRatesPref: "Skip", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
  graph: {graphId: "p02r", records: [{referenceId: "q1", record: {attributes: {type: "Quote", method: "PATCH", id: $id}, Description: "P02 reprice"}},
    {referenceId: "l1", record: ({attributes: {type: "QuoteLineItem", method: "PATCH", id: $lid}} + $line)}]}}')
  rest POST /connect/rev/sales-transaction/actions/place "$RB" | jq -c '{isSuccess, errorResponse}'; sleep 8; show; }
echo "===== A. reprice saved quote (Monthly)"; place '{"Quantity": 2}'
echo "===== B. change to Annual and price in the same call"; place '{"BillingFrequency": "Annual"}'
echo "===== C. reprice again (Annual already saved)"; place '{"Quantity": 2}'
echo "QUOTE $(q "SELECT Name, QuoteNumber, Hierarchy_Location_Count__c, StartDate, RLM_TermMonths__c, TotalPrice, CalculationStatus FROM Quote WHERE Id = '$QUOTE'")"
echo "LINE $(q "SELECT Id, Quantity, ListPrice, UnitPrice, NetUnitPrice, TotalPrice, Discount, SubscriptionTerm, SubscriptionTermUnit, BillingFrequency, Volume_Location_Count__c, Billing_Period_Months__c, StartDate, EndDate FROM QuoteLineItem WHERE QuoteId = '$QUOTE'")"
LINE=$(q "SELECT Id FROM QuoteLineItem WHERE QuoteId = '$QUOTE' LIMIT 1" | jq -r '.[0].Id')
echo "ADJUSTMENTS $(q "SELECT FIELDS(STANDARD) FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = '$LINE' LIMIT 20" | jq -c 'if type=="array" then [.[] | del(.attributes) | with_entries(select(.value != null and (.key|test("Created|LastModified|SystemModstamp|IsDeleted|Owner")|not)))] else . end')"
