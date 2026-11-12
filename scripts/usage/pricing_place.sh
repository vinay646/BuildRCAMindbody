#!/usr/bin/env bash
# P02 via the standard Place Sales Transaction API (what the quote UI uses): Annual, with and without Subscription Term.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
ACC=$(q "SELECT Id FROM Account WHERE Name = 'Pulse Fitness Brands' LIMIT 1" | jq -r '.[0].Id')
CON=$(q "SELECT Id FROM Contact WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id')
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name = 'North America & Asia (USD)'" | jq -r '.[0].Id')
PBE=$(q "SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ULT' AND Pricebook2Id = '$PB' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1")
PBEID=$(echo "$PBE" | jq -r '.[0].Id'); PROD=$(echo "$PBE" | jq -r '.[0].Product2Id')
TODAY=$(date -u +%Y-%m-%d); END=$(date -u -d '+36 months -1 day' +%Y-%m-%d); STAMP=$(date -u +%m%d-%H%M)
T=$(q "SELECT Id FROM BillingTreatment WHERE Name = 'Mindbody Billing Treatment - Advance'" | jq -r '.[0].Id')
LE=$(q "SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - US'" | jq -r '.[0].Id')
for V in ${VARIANTS:-legal}; do
  echo "===== variant $V"
  OPP=$(sf data create record --sobject Opportunity --values "Name='P02 $V $STAMP' AccountId=$ACC StageName=Prospecting CloseDate=$TODAY Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
  EXTRA='{}'; [ "$V" = "with-term" ] && EXTRA='{"SubscriptionTerm": 36}'
  [ "$V" = "legal" ] && EXTRA="{\"LegalEntityId\": \"$LE\"}"
  [ "${V#treatment}" != "$V" ] && EXTRA="{\"BillingTreatmentId\": \"$T\"}"
  [ "$V" = "treatment-change" ] && echo "set CanChangeBillingFrequency=true: $(sf data update record --sobject BillingTreatment --record-id "$T" --values "CanChangeBillingFrequency=true" --target-org target --json | jq -c '{status, message}')"
  BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg prod "$PROD" --arg pbe "$PBEID" --arg d "$TODAY" --arg e "$END" --arg con "$CON" --argjson x "$EXTRA" '{
    pricingPref: "System", catalogRatesPref: "Skip", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
    graph: {graphId: "p02", records: [
      {referenceId: "q1", record: ({attributes: {type: "Quote", method: "POST"}, Name: "P02 Pricing Test", OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con, StartDate: $d, RLM_TermMonths__c: 36} + (if $x.LegalEntityId then {LegalEntityId: $x.LegalEntityId} else {} end))},
      {referenceId: "l1", record: ({attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}", Product2Id: $prod,
        PricebookEntryId: $pbe, Quantity: 2, StartDate: $d, EndDate: $e, PeriodBoundary: "Anniversary", BillingFrequency: "Annual"} + $x)}]}}')
  rest POST /connect/rev/sales-transaction/actions/place "$BODY" | jq -c '{isSuccess, errorResponse, salesTransactionId}'
  sleep 8
  QUOTE=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' LIMIT 1" | jq -r '.[0].Id // empty')
  echo "QUOTE $(q "SELECT QuoteNumber, CalculationStatus, TotalPrice FROM Quote WHERE Id = '$QUOTE'")"
  echo "LINE $(q "SELECT BillingFrequency, BillingTreatmentId, Quantity, SubscriptionTerm, ListPrice, NetUnitPrice, TotalPrice FROM QuoteLineItem WHERE QuoteId = '$QUOTE'")"
done
