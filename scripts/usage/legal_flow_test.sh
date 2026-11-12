#!/usr/bin/env bash
# End to end: Pulse quote via Place Sales Transaction, no legal entity / treatment given – the flows fill them.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
echo "POLICIES $(q "SELECT Name, Status, BillingTreatmentSelection, DefaultBillingTreatment.Name FROM BillingPolicy WHERE Name LIKE 'Mindbody%'")"
echo "TREATMENTS $(q "SELECT Name, Status, LegalEntity.Name, CurrencyIsoCode, CanChangeBillingFrequency, BillingPolicy.Name FROM BillingTreatment WHERE Name LIKE 'Mindbody%' ORDER BY Name")"
echo "PRODUCTS $(q "SELECT ProductCode, BillingPolicy.Name FROM Product2 WHERE ProductCode IN ('MB-ULT','MB-SMS','MB-PAY','MB-HW-TRM')")"
ACC=$(q "SELECT Id, MB_Region__c, MB_Legal_Entity__r.Name FROM Account WHERE Name = 'Pulse Fitness Brands' LIMIT 1"); echo "ACCOUNT $ACC"; ACC=$(echo "$ACC" | jq -r '.[0].Id')
CON=$(q "SELECT Id FROM Contact WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id')
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name = 'North America & Asia (USD)'" | jq -r '.[0].Id')
pbe() { q "SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = '$1' AND Pricebook2Id = '$PB' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1"; }
U=$(pbe MB-ULT); S=$(pbe MB-SMS); echo "ULT $U SMS $S"
TODAY=$(date -u +%Y-%m-%d); END=$(date -u -d '+36 months -1 day' +%Y-%m-%d); STAMP=$(date -u +%m%d-%H%M)
OPP=$(sf data create record --sobject Opportunity --values "Name='Legal Entity Test $STAMP' AccountId=$ACC StageName=Prospecting CloseDate=$TODAY Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
echo "OPP $(q "SELECT Name, MB_Legal_Entity__c FROM Opportunity WHERE Id = '$OPP'")"
BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg d "$TODAY" --arg e "$END" --arg con "$CON" --argjson u "$U" --argjson s "$S" '{
  pricingPref: "System", catalogRatesPref: "Skip", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
  graph: {graphId: "le", records: [
    {referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: "Legal Entity Test", OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con, StartDate: $d, RLM_TermMonths__c: 36}},
    {referenceId: "l1", record: {attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}", Product2Id: $u[0].Product2Id,
      PricebookEntryId: $u[0].Id, Quantity: 2, StartDate: $d, EndDate: $e, PeriodBoundary: "Anniversary", BillingFrequency: "Annual"}},
    {referenceId: "l2", record: {attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}", Product2Id: $s[0].Product2Id,
      PricebookEntryId: $s[0].Id, Quantity: 1, StartDate: $d, PeriodBoundary: "Anniversary", BillingFrequency: "Monthly"}}]}}')
rest POST /connect/rev/sales-transaction/actions/place "$BODY" | jq -c '{isSuccess, errorResponse}'
sleep 10
QUOTE=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' LIMIT 1" | jq -r '.[0].Id // empty')
echo "QUOTE $(q "SELECT QuoteNumber, LegalEntity.Name, CalculationStatus, TotalPrice FROM Quote WHERE Id = '$QUOTE'")"
echo "LINES $(q "SELECT Product2.ProductCode, BillingFrequency, LegalEntity.Name, BillingTreatment.Name, ListPrice, NetUnitPrice, TotalPrice FROM QuoteLineItem WHERE QuoteId = '$QUOTE'")"
