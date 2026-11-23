#!/usr/bin/env bash
# CREATES then DELETES test data in QA: MR-143 #4 (TAM quote term 12 -> 24 blocked) and #5 (term 18 blocked)
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
mk() { sf data create record --sobject "$1" --values "$2" --target-org target --json 2>&1; }
up() { sf data update record --sobject "$1" --record-id "$2" --values "$3" --target-org target --json 2>&1 | jq -r 'if .status == 0 then "SAVED" else "BLOCKED: " + (.message | .[0:250]) end'; }
D=$(date -u +%Y-%m-%d); E=$(date -u -d '+1 year -1 day' +%Y-%m-%d); S=$(date -u +%H%M%S)
ACC=$(sf api request rest "/services/data/v$ORG_API/sobjects/Account" --method POST --header "Sforce-Duplicate-Rule-Header: allowSave=true" --body "$(jq -nc --arg n "QA TEST MR-143 $S" --arg st "4$S Test St" '{Name:$n, Account_Level__c:"Corporate", Vertical__c:"Fitness", Region__c:"NA", BillingStreet:$st, BillingCity:"Austin", BillingState:"Texas", BillingPostalCode:"73301", BillingCountry:"United States", ShippingStreet:$st, ShippingCity:"Austin", ShippingState:"Texas", ShippingPostalCode:"73301", ShippingCountry:"United States"}')" --target-org target 2>&1 | jq -r '.id // empty')
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name LIKE 'North America%' AND IsActive = true LIMIT 1" | jq -r '.[0].Id')
OPP=$(mk Opportunity "Name='QA TEST MR-143 $S' AccountId=$ACC StageName=Prospecting CloseDate=$D Pricebook2Id=$PB" | jq -r '.result.id // empty')
QT=$(mk Quote "Name='QA TEST MR-143' OpportunityId=$OPP Pricebook2Id=$PB RLM_TermMonths__c=12 StartDate=$D" | jq -r '.result.id // empty')
T=$(q "SELECT Id, Product2Id, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode = 'MB-TAM' AND Pricebook2Id = '$PB' AND IsActive = true LIMIT 1" | jq -c '.[0]')
echo "setup: account $ACC quote $QT TAM entry $(echo "$T" | jq -c '{m: .ProductSellingModel.Name}')"
R=$(mk QuoteLineItem "QuoteId=$QT Product2Id=$(echo "$T" | jq -r .Product2Id) PricebookEntryId=$(echo "$T" | jq -r .Id) Quantity=1 UnitPrice=0 StartDate=$D EndDate=$E BillingFrequency=Monthly")
echo "TAM line on 12-month quote: $(echo "$R" | jq -r 'if .status == 0 then "added" else "error: " + (.message | .[0:200]) end')"
echo "TEST 4 (TAM quote, term 12 -> 24): $(up Quote $QT 'RLM_TermMonths__c=24')"
echo "TEST 5 (term 18): $(up Quote $QT 'RLM_TermMonths__c=18')"
echo "term now: $(q "SELECT RLM_TermMonths__c FROM Quote WHERE Id = '$QT'" | jq -r '.[0].RLM_TermMonths__c')"
[ -n "$OPP" ] && sf data delete record --sobject Opportunity --record-id $OPP --target-org target --json >/dev/null 2>&1
echo "cleanup: $(sf data delete record --sobject Account --record-id $ACC --target-org target --json 2>&1 | jq -r .status)"
