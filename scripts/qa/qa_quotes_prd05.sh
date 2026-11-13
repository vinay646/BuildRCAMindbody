#!/usr/bin/env bash
# CREATES test quotes on the "Test" account for MB-PRD-05 hardware.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)]'; }
mk() { sf api request rest "$API/sobjects/$1" --method POST --header "Sforce-Duplicate-Rule-Header: allowSave=true" --body "$2" --target-org target 2>&1 | tee mk.json | jq -r '.id // empty'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
INST=$(sf org display --target-org target --json | jq -r '.result.instanceUrl' | sed 's/\.my\.salesforce\.com/.lightning.force.com/')
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name = 'North America & Asia (USD)' AND IsActive = true" | jq -r '.[0].Id')
echo "pricebook=$PB"
pbe() { q "SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = '$PB' AND Product2.ProductCode = '$1' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1"; }
CT=$(sf api request rest "$API/sobjects/Account/describe" --target-org target | jq -r '[.fields[] | select(.name=="Contract_Type__c") | .picklistValues[] | select(.active) | .value] | (map(select(. == "Master"))[0] // .[0]) // empty')
echo "contract type values: $(sf api request rest "$API/sobjects/Account/describe" --target-org target | jq -c '[.fields[] | select(.name=="Contract_Type__c") | .picklistValues[] | select(.active) | .value]')"
ACC=${QA_ACCOUNT_ID:-001i800000A8qodAAB}
echo "ACCOUNT $(q "SELECT Id, Name, CurrencyIsoCode, BillingCountry FROM Account WHERE Id = '$ACC'")"
[ -z "$ACC" ] && ACC=$(mk Account '{"Name":"QA Test - Services","Contract_Type__c":"'"$CT"'","CurrencyIsoCode":"USD","BillingStreet":"100 QA Street","BillingCity":"San Luis Obispo","BillingState":"California","BillingPostalCode":"93401","BillingCountry":"United States","ShippingStreet":"100 QA Street","ShippingCity":"San Luis Obispo","ShippingState":"California","ShippingPostalCode":"93401","ShippingCountry":"United States"}')
[ -z "$ACC" ] && { echo "ACCOUNT ERROR $(head -c 1500 mk.json)"; echo "ACCOUNT FLOWS $(q "SELECT ApiName, Label, ProcessType, TriggerType FROM FlowDefinitionView WHERE IsActive = true AND TriggerObjectOrEventLabel = 'Account'")"; echo "RECORD TYPES $(q "SELECT Name, DeveloperName, IsActive FROM RecordType WHERE SobjectType = 'Account'")"; exit 1; }
CON=$(q "SELECT Id FROM Contact WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id // empty')
[ -z "$CON" ] && CON=$(mk Contact "{\"FirstName\":\"QA\",\"LastName\":\"Services Tester\",\"Email\":\"qa.services@example.org\",\"AccountId\":\"$ACC\"}")
echo "account=$ACC contact=$CON"
TODAY=$(date -u +%Y-%m-%d)
mkquote() { # $1 name, $2 lines json, $3 config method (Skip|System), $4 "noaddr" to leave Ship-To empty
  OPP=$(q "SELECT Id FROM Opportunity WHERE AccountId = '$ACC' AND Name = '$1' LIMIT 1" | jq -r '.[0].Id // empty')
  [ -z "$OPP" ] && OPP=$(mk Opportunity "{\"Name\":\"$1\",\"AccountId\":\"$ACC\",\"StageName\":\"Prospecting\",\"CloseDate\":\"$TODAY\",\"Pricebook2Id\":\"$PB\",\"CurrencyIsoCode\":\"USD\"}")
  BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg con "$CON" --arg n "$1" --argjson lines "$2" --arg cfg "${3:-Skip}" --arg noaddr "${4:-}" '{
    pricingPref: "System", catalogRatesPref: "Skip", configurationPref: {configurationMethod: $cfg},
    graph: {graphId: "qa", records: ([{referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: $n, OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con,
      BillingStreet: "100 QA Street", BillingCity: "San Luis Obispo", BillingState: "California", BillingPostalCode: "93401", BillingCountry: "United States"}
      + (if $noaddr == "noaddr" then {} else {ShippingStreet: "100 QA Street", ShippingCity: "San Luis Obispo", ShippingState: "California", ShippingPostalCode: "93401", ShippingCountry: "United States"} end)}]
      + ($lines | to_entries | map({referenceId: ("l" + (.key|tostring)), record: ({attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}"} + .value)})))}}')
  RES=$(rest POST /connect/rev/sales-transaction/actions/place "$BODY")
  echo "$RES" | jq -c '{success: .success, errors: [.errorResponse[]? | {message, errorCode}]}' 2>/dev/null || echo "$RES" | head -c 800
  QID=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' LIMIT 1" | jq -r '.[0].Id // empty')
  echo "QUOTE $1 => $INST/lightning/r/Quote/$QID/view"
  [ -n "$QID" ] && echo "LINES $(q "SELECT Product2.ProductCode, Quantity, UnitPrice, NetUnitPrice, TotalPrice, StartDate, EndDate, SubscriptionTerm, BillingFrequency, ProductSellingModel.Name FROM QuoteLineItem WHERE QuoteId = '$QID' ORDER BY Product2.ProductCode")"
}
line() { # code qty [end]
  P=$(pbe "$1"); jq -nc --arg p "$(echo "$P" | jq -r '.[0].Product2Id')" --arg e "$(echo "$P" | jq -r '.[0].Id')" --arg d "$TODAY" --arg end "${3:-}" --argjson qty "$2" --arg freq "${4:-}" \
    '{Product2Id: $p, PricebookEntryId: $e, Quantity: $qty, StartDate: $d} + (if $end != "" then {EndDate: $end, PeriodBoundary: "Anniversary", BillingFrequency: "Monthly"} else {} end)'
}
L1=$(jq -nc --argjson a "$(line MB-HW-RDR 1)" '[$a]')
mkquote "QA MR-76 Q1 - Card reader without Payments" "$L1" System
L2=$(jq -nc --argjson a "$(line MB-PAY 1)" --argjson b "$(line MB-HW-RDR 1)" '[$a,$b]')
mkquote "QA MR-76 Q2 - Card reader and Payments, no Ship-To" "$L2" Skip noaddr
[ -n "${QID:-}" ] && echo "Q2 SHIP-TO $(q "SELECT ShippingStreet, ShippingCity, ShippingCountry FROM Quote WHERE Id = '$QID'")"
