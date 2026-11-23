#!/usr/bin/env bash
# CREATES then DELETES test data in QA: adds Enterprise to a 24-month quote on account ACC (default 001i800000B4mpJAAR) and reports blocked or allowed, with the account's hierarchy and master contracts
ACC=${ACC:-001i800000B4mpJAAR}
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
mk() { sf data create record --sobject "$1" --values "$2" --target-org target --json 2>&1; }
D=$(date -u +%Y-%m-%d); E=$(date -u -d '+2 years -1 day' +%Y-%m-%d)
A=$(q "SELECT Name, Account_Level__c, ParentId, Parent.Name, Root_Account__c, Root_Account__r.Name FROM Account WHERE Id = '$ACC'" | jq -c '.[0] | {Name, Level: .Account_Level__c, Parent: .Parent.Name, Root: .Root_Account__r.Name, RootId: .Root_Account__c}')
echo "ACCOUNT $A"; ROOT=$(echo "$A" | jq -r '.RootId // empty')
echo "MASTER FIELDS $(sf data query --query "SELECT FIELDS(CUSTOM) FROM Account WHERE Id = '$ACC' LIMIT 1" --target-org target --json 2>/dev/null | jq -c '.result.records[0] | with_entries(select(.value != null and .value != false and (.key|test("Root|Master|Contract|Level";"i"))))')"
echo "OWN CONTRACTS $(q "SELECT ContractNumber, Status, Contract_Type__c FROM Contract WHERE AccountId = '$ACC'" | jq -c '[.[] | [.ContractNumber, .Status, .Contract_Type__c]]')"
[ -n "$ROOT" ] && echo "ROOT CONTRACTS $(q "SELECT ContractNumber, Status, Contract_Type__c FROM Contract WHERE AccountId = '$ROOT'" | jq -c '[.[] | [.ContractNumber, .Status, .Contract_Type__c]]')"
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name LIKE 'North America%' AND IsActive = true LIMIT 1" | jq -r '.[0].Id')
E1=$(q "SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ENT' AND Pricebook2Id = '$PB' AND IsActive = true AND ProductSellingModel.Name = 'Term Monthly' LIMIT 1" | jq -c '.[0]')
OPP=$(mk Opportunity "Name='QA TEST Enterprise check' AccountId=$ACC StageName=Prospecting CloseDate=$D Pricebook2Id=$PB" | jq -r '.result.id // empty')
R=$(mk Quote "Name='QA TEST Enterprise check' OpportunityId=$OPP Pricebook2Id=$PB RLM_TermMonths__c=24 StartDate=$D"); QT=$(echo "$R" | jq -r '.result.id // empty')
[ -z "$QT" ] && echo "quote error: $(echo "$R" | jq -r .message | head -c 300)"
R=$(mk QuoteLineItem "QuoteId=$QT Product2Id=$(echo "$E1" | jq -r .Product2Id) PricebookEntryId=$(echo "$E1" | jq -r .Id) Quantity=1 UnitPrice=0 StartDate=$D EndDate=$E BillingFrequency=Monthly")
echo "ADD ENTERPRISE: status $(echo "$R" | jq -r .status) | $(echo "$R" | jq -r '.message // "line added"' | head -c 300) | lines on quote: $(q "SELECT COUNT(Id) n FROM QuoteLineItem WHERE QuoteId = '$QT'" | jq -r '.[0].n')"
[ -n "$OPP" ] && echo "cleanup: $(sf data delete record --sobject Opportunity --record-id $OPP --target-org target --json 2>&1 | jq -r .status)"
