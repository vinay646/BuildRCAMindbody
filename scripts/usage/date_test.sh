#!/usr/bin/env bash
# Test: quote Start Date / Term drive line dates (flows MB_Quote_End_Date, MB_Quote_Dates_To_Lines, MB_Quote_Line_Default_Dates)
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '.result.records // []'; }
show() { echo "QUOTE $(q "SELECT StartDate, RLM_TermMonths__c, RLM_EndDate__c FROM Quote WHERE Id = '$QUOTE'" | jq -c '.[0] | del(.attributes)')"
  q "SELECT Product2.ProductCode, SellingModelType, StartDate, EndDate, ParentQuoteLineItemId FROM QuoteLineItem WHERE QuoteId = '$QUOTE' ORDER BY ParentQuoteLineItemId NULLS FIRST" | jq -r '.[] | "  \(.Product2.ProductCode) | \(.SellingModelType) | start \(.StartDate) | end \(.EndDate) | \(if .ParentQuoteLineItemId then "component" else "top" end)"'; }
QUOTE=$(q "SELECT Id FROM Quote WHERE MB_Prior_System__c = 'Vagaro' ORDER BY LastModifiedDate DESC LIMIT 1" | jq -r '.[0].Id')
ORIG=$(q "SELECT StartDate, RLM_TermMonths__c FROM Quote WHERE Id = '$QUOTE'")
OS=$(echo "$ORIG" | jq -r '.[0].StartDate'); OT=$(echo "$ORIG" | jq -r '.[0].RLM_TermMonths__c')
echo "quote=$QUOTE original start=$OS term=$OT"
echo "===== 0. before"; show
echo "===== 1. set Start Date 2026-12-01, Term 24"
sf data update record --sobject Quote --record-id "$QUOTE" --values "StartDate=2026-12-01 RLM_TermMonths__c=24" --target-org target --json | jq -c '{status, message}'
show
echo "===== 2. add Technical Account Management (new line)"
PB=$(q "SELECT Pricebook2Id FROM Quote WHERE Id = '$QUOTE'" | jq -r '.[0].Pricebook2Id')
PBE=$(q "SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = '$PB' AND Product2.ProductCode = 'MB-TAM' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1")
BODY=$(jq -nc --arg q "$QUOTE" --arg p "$(echo "$PBE" | jq -r '.[0].Product2Id')" --arg e "$(echo "$PBE" | jq -r '.[0].Id')" '{pricingPref:"Skip",catalogRatesPref:"Skip",taxPref:"Skip",configurationPref:{configurationMethod:"Skip"},
  graph:{graphId:"addtam",records:[{referenceId:"q",record:{attributes:{type:"Quote",method:"PATCH",id:$q}}},
  {referenceId:"l1",record:{attributes:{type:"QuoteLineItem",method:"POST"},QuoteId:$q,Product2Id:$p,PricebookEntryId:$e,Quantity:1,StartDate:"2026-11-12",PeriodBoundary:"Anniversary",BillingFrequency:"Monthly"}}]}}')
sf api request rest "$API/connect/rev/sales-transaction/actions/place" --method POST --body "$BODY" --target-org target 2>&1 | jq -c '{isSuccess, errorResponse}'
sleep 8; show
echo "===== 3. restore Start Date $OS, Term $OT"
sf data update record --sobject Quote --record-id "$QUOTE" --values "StartDate=$OS RLM_TermMonths__c=$OT" --target-org target --json | jq -c '{status, message}'
show
