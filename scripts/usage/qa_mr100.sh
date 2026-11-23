#!/usr/bin/env bash
# CREATES then DELETES test data in QA: MR-100 volume band - Ultimate 12 months monthly at 1, 4, 14 locations on a new account, and 2 locations on an account with active locations
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
D=$(date -u +%Y-%m-%d); E=$(date -u -d '+1 year -1 day' +%Y-%m-%d); S=$(date -u +%H%M%S)
echo "ACCOUNT LOCATION FIELDS $(sf sobject describe --sobject Account --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.name|test("ocation";"i")) | .name]')"
echo "QUOTE LOCATION FIELDS $(sf sobject describe --sobject Quote --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.name|test("ocation";"i")) | .name]') QLI: $(sf sobject describe --sobject QuoteLineItem --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.name|test("ocation|Volume";"i")) | .name]')"
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name LIKE 'North America%' AND IsActive = true LIMIT 1" | jq -r '.[0].Id')
U=$(q "SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ULT' AND Pricebook2Id = '$PB' AND IsActive = true AND ProductSellingModel.Name = 'Term Monthly' LIMIT 1" | jq -c '.[0]')
NEWACC=$(sf api request rest "$API/sobjects/Account" --method POST --header "Sforce-Duplicate-Rule-Header: allowSave=true" --body "$(jq -nc --arg n "QA TEST MR-100 $S" --arg st "5$S Test St" '{Name:$n, Account_Level__c:"Corporate", Vertical__c:"Fitness", Region__c:"NA", BillingStreet:$st, BillingCity:"Austin", BillingState:"Texas", BillingPostalCode:"73301", BillingCountry:"United States", ShippingStreet:$st, ShippingCity:"Austin", ShippingState:"Texas", ShippingPostalCode:"73301", ShippingCountry:"United States"}')" --target-org target 2>&1 | jq -r '.id // empty')
OPPS=()
run() { # $1 label $2 account $3 qty
  OPP=$(sf data create record --sobject Opportunity --values "Name='QA TEST MR-100 $1' AccountId=$2 StageName=Prospecting CloseDate=$D Pricebook2Id=$PB" --target-org target --json | jq -r '.result.id // empty'); OPPS+=($OPP)
  B=$(jq -nc --arg o "$OPP" --arg pb "$PB" --arg d "$D" --arg e "$E" --argjson u "$U" --argjson n $3 '{pricingPref:"System", catalogRatesPref:"Skip", configurationPref:{configurationMethod:"Skip"}, taxPref:"Skip", graph:{graphId:"g", records:[
    {referenceId:"q1", record:{attributes:{type:"Quote", method:"POST"}, Name:"QA TEST MR-100", OpportunityId:$o, Pricebook2Id:$pb, StartDate:$d, RLM_TermMonths__c:12}},
    {referenceId:"l1", record:{attributes:{type:"QuoteLineItem", method:"POST"}, QuoteId:"@{q1.id}", Product2Id:$u.Product2Id, PricebookEntryId:$u.Id, Quantity:$n, StartDate:$d, EndDate:$e, BillingFrequency:"Monthly", PeriodBoundary:"Anniversary"}}]}}')
  R=$(sf api request rest "$API/connect/rev/sales-transaction/actions/place" --method POST --body "$B" --target-org target 2>&1)
  [ "$(echo "$R" | jq -r .isSuccess 2>/dev/null)" != "true" ] && { echo "$1: place failed $(echo "$R" | tr -d '\n' | head -c 400)"; return; }
  sleep 4; QT=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' LIMIT 1" | jq -r '.[0].Id')
  echo "$1 (qty $3): $(q "SELECT ListPrice, NetUnitPrice, Discount FROM QuoteLineItem WHERE QuoteId = '$QT'" | jq -c '.[0]') | adjustments $(q "SELECT AdjustmentSource, AdjustmentType, AdjustmentValue, AdjustmentAmount FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = '$QT'" | jq -c '[.[] | [.AdjustmentSource, .AdjustmentValue, .AdjustmentAmount]]')"
}
run "1 loc new acct" $NEWACC 1
run "4 loc new acct" $NEWACC 4
run "14 loc new acct" $NEWACC 14
EX=$(q "SELECT Id, Name, Active_Location_Count__c FROM Account WHERE ParentId = null AND Active_Location_Count__c > 2 ORDER BY Active_Location_Count__c LIMIT 1" 2>&1)
echo "EXISTING $EX"
EID=$(echo "$EX" | jq -r '.[0].Id // empty' 2>/dev/null); [ -n "$EID" ] && run "existing +2" $EID 2
for o in "${OPPS[@]}"; do sf data delete record --sobject Opportunity --record-id $o --target-org target --json >/dev/null 2>&1; done
echo "cleanup: $(sf data delete record --sobject Account --record-id $NEWACC --target-org target --json 2>&1 | jq -r .status)"
