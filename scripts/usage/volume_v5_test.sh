#!/usr/bin/env bash
# Activate pricing procedure v5 (location volume = hierarchy + new locations on the quote), sync, then price test quotes
# through the standard Place Sales Transaction API. CREATES test opportunities/quotes on Pulse Fitness Brands.
# If pricing fails, version 4 is re-activated automatically.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
./scripts/usage/activate_v5.sh
sleep 20
ACC=$(q "SELECT Id FROM Account WHERE Name = 'Pulse Fitness Brands' LIMIT 1" | jq -r '.[0].Id')
CON=$(q "SELECT Id FROM Contact WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id')
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name = 'North America & Asia (USD)'" | jq -r '.[0].Id')
LE=$(q "SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - US'" | jq -r '.[0].Id')
pbe() { q "SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Product2.ProductCode = '$1' AND Pricebook2Id = '$PB' AND CurrencyIsoCode = 'USD' AND IsActive = true AND ProductSellingModel.Name = 'Term Monthly' LIMIT 1" | jq -c '.[0]'; }
ULT=$(pbe MB-ULT); STR=$(pbe MB-STR)
echo "ULT $ULT"; echo "STR $STR"
TODAY=$(date -u +%Y-%m-%d); END=$(date -u -d '+12 months -1 day' +%Y-%m-%d); STAMP=$(date -u +%m%d-%H%M)
band() { awk -v c="$1" 'BEGIN{p=0; if(c>=4)p=5; if(c>=11)p=10; if(c>=51)p=15; if(c>=201)p=20; print p}'; }
FAILED=0
run() {  # $1 name, $2 lines json array of [pbeJson, qty]
  local NAME=$1 LINES=$2
  OPP=$(sf data create record --sobject Opportunity --values "Name='V5 volume $NAME $STAMP' AccountId=$ACC StageName=Prospecting CloseDate=$TODAY Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
  BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg d "$TODAY" --arg e "$END" --arg con "$CON" --arg le "$LE" --argjson lines "$LINES" '{
    pricingPref: "System", catalogRatesPref: "Skip", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
    graph: {graphId: "v5", records: ([{referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: "V5 volume test", OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con, StartDate: $d, RLM_TermMonths__c: 12, LegalEntityId: $le}}]
      + [$lines | to_entries[] | {referenceId: "l\(.key)", record: {attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}", Product2Id: .value[0].Product2Id,
         PricebookEntryId: .value[0].Id, Quantity: .value[1], StartDate: $d, EndDate: $e, PeriodBoundary: "Anniversary", BillingFrequency: "Monthly", LegalEntityId: $le}}])}}')
  R=$(rest POST /connect/rev/sales-transaction/actions/place "$BODY"); echo "== $NAME place: $(echo "$R" | jq -c '{isSuccess, errorResponse}' 2>/dev/null || echo "$R" | head -c 600)"
  sleep 10
  QUOTE=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' LIMIT 1" | jq -r '.[0].Id // empty')
  QI=$(q "SELECT QuoteNumber, CalculationStatus, Hierarchy_Location_Count__c FROM Quote WHERE Id = '$QUOTE'"); echo "   quote $QI"
  H=$(echo "$QI" | jq -r '.[0].Hierarchy_Location_Count__c // 0'); NEWQ=$(echo "$LINES" | jq '[.[] | .[1]] | add'); C=$(awk -v a="$H" -v b="$NEWQ" 'BEGIN{print a+b}'); P=$(band "$C")
  echo "   expected: hierarchy $H + new $NEWQ = $C locations -> $P%"
  for row in $(q "SELECT Product2.ProductCode, Quantity, ListPrice, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '$QUOTE' AND Product2.ProductCode IN ('MB-ULT','MB-STR')" | jq -c '.[]'); do
    LP=$(echo "$row" | jq -r .ListPrice); NP=$(echo "$row" | jq -r .NetUnitPrice); EXP=$(awk -v l="$LP" -v p="$P" 'BEGIN{printf "%.2f", l*(100-p)/100}')
    OK=$(awk -v n="$NP" -v e="$EXP" 'BEGIN{print (n!="" && (n-e<0.01 && e-n<0.01))?"PASS":"FAIL"}'); [ "$OK" = FAIL ] && FAILED=1
    echo "   $OK $(echo "$row" | jq -c '{code: .Product2.ProductCode, qty: .Quantity, list: .ListPrice, net: .NetUnitPrice}') expected net $EXP"
  done
  echo "$R" | jq -e '.isSuccess == true' > /dev/null 2>&1 || FAILED=1
}
run "ULT-2" "[[${ULT},2]]"
# one plan per quote (CR-01), so the band change is shown with one Ultimate line: 12 + 40 = 52 -> 15%, 12 + 189 = 201 -> 20%
run "ULT-40" "[[${ULT},40]]"
run "ULT-189" "[[${ULT},189]]"
echo "== standard quantity tiers still present: $(q "SELECT COUNT(Id) n FROM PriceAdjustmentTier WHERE PriceAdjustmentSchedule.Name = 'Standard Price Adjustment Tier'")"
if [ "$FAILED" = 1 ]; then echo "== FAILURES: re-activating version 4"; ./scripts/usage/activate_v4.sh; else echo "== ALL PASS: version 5 stays active"; fi
