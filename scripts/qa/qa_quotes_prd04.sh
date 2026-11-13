#!/usr/bin/env bash
# CREATES test data in the testing org: account "QA Test - Services", contact, opportunity and 2 quotes for MB-PRD-04.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)]'; }
mk() { sf api request rest "$API/sobjects/$1" --method POST --header "Sforce-Duplicate-Rule-Header: allowSave=true" --body "$2" --target-org target 2>&1 | tee mk.json | jq -r '.id // empty'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
INST=$(sf org display --target-org target --json | jq -r '.result.instanceUrl' | sed 's/\.my\.salesforce\.com/.lightning.force.com/')
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name = 'North America & Asia (USD)' AND IsActive = true" | jq -r '.[0].Id')
echo "pricebook=$PB"
pbe() { q "SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = '$PB' AND Product2.ProductCode = '$1' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1"; }
ACC=$(q "SELECT Id FROM Account WHERE Name = 'QA Test - Services' LIMIT 1" | jq -r '.[0].Id // empty')
[ -z "$ACC" ] && ACC=$(mk Account '{"Name":"QA Test - Services","CurrencyIsoCode":"USD","BillingStreet":"100 QA Street","BillingCity":"San Luis Obispo","BillingState":"California","BillingPostalCode":"93401","BillingCountry":"United States","ShippingStreet":"100 QA Street","ShippingCity":"San Luis Obispo","ShippingState":"California","ShippingPostalCode":"93401","ShippingCountry":"United States"}')
[ -z "$ACC" ] && { echo "ACCOUNT ERROR $(head -c 1500 mk.json)"; exit 1; }
CON=$(q "SELECT Id FROM Contact WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id // empty')
[ -z "$CON" ] && CON=$(mk Contact "{\"FirstName\":\"QA\",\"LastName\":\"Services Tester\",\"Email\":\"qa.services@example.org\",\"AccountId\":\"$ACC\"}")
echo "account=$ACC contact=$CON"
TODAY=$(date -u +%Y-%m-%d)
mkquote() { # $1 name, $2 lines json array (jq objects without QuoteId)
  OPP=$(mk Opportunity "{\"Name\":\"$1\",\"AccountId\":\"$ACC\",\"StageName\":\"Prospecting\",\"CloseDate\":\"$TODAY\",\"Pricebook2Id\":\"$PB\",\"CurrencyIsoCode\":\"USD\"}")
  BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg con "$CON" --arg n "$1" --argjson lines "$2" '{
    pricingPref: "System", catalogRatesPref: "Skip", configurationPref: {configurationMethod: "System"},
    graph: {graphId: "qa", records: ([{referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: $n, OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con,
      BillingStreet: "100 QA Street", BillingCity: "San Luis Obispo", BillingState: "California", BillingPostalCode: "93401", BillingCountry: "United States",
      ShippingStreet: "100 QA Street", ShippingCity: "San Luis Obispo", ShippingState: "California", ShippingPostalCode: "93401", ShippingCountry: "United States"}}]
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
END12=$(date -u -d '+12 months -1 day' +%Y-%m-%d); END24=$(date -u -d '+24 months -1 day' +%Y-%m-%d)
L1=$(jq -nc --argjson a "$(line MB-STR 1 $END12)" --argjson b "$(line MB-TAM 1 $END12)" --argjson c "$(line MB-IMP 1)" --argjson d "$(line MB-DCV 1)" --argjson e "$(line MB-CON 5)" '[$a,$b,$c,$d,$e]')
mkquote "QA MR-75 Q1 - Starter with all services (TAM 12 months)" "$L1"
L2=$(jq -nc --argjson a "$(line MB-STR 1 $END24)" --argjson b "$(line MB-TAM 1 $END24)" '[$a,$b]')
mkquote "QA MR-75 Q2 - TAM on a 24-month term" "$L2"
