#!/usr/bin/env bash
# CREATES test amendment + renewal quotes on the MR103 Q2C04 test account (standard initiateAmendment / initiateRenewal)
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
acc=$(q "SELECT Id FROM Account WHERE Name LIKE 'MR103 Q2C04%' LIMIT 1" '.result.records[0].Id' | tr -d '"')
a=$(q "SELECT Id FROM Asset WHERE AccountId = '$acc' AND Name = 'Ultimate' LIMIT 1" '.result.records[0].Id' | tr -d '"')
echo "OriginalActionType values: $(sf sobject describe --sobject Quote --target-org target --json | jq -c '[.result.fields[] | select(.name=="OriginalActionType") | .picklistValues[]?.value]')"
echo "Opp Type values: $(sf sobject describe --sobject Opportunity --target-org target --json | jq -c '[.result.fields[] | select(.name=="Type") | .picklistValues[]? | select(.active) | .value]')"
d=$(date -u -d '+1 day' +%Y-%m-%dT00:00:00Z)
echo "amend: $(sf api request rest "$API/actions/standard/initiateAmendment" --method POST --body "{\"inputs\":[{\"amendAssetIds\":[\"$a\"],\"amendStartDate\":\"$d\",\"quantityChange\":1,\"amendOutputType\":\"Quote\"}]}" --target-org target 2>&1 | jq -c '.[0] | {isSuccess, outputValues, errors}')"
echo "renew: $(sf api request rest "$API/actions/standard/initiateRenewal" --method POST --body "{\"inputs\":[{\"renewAssetIds\":[\"$a\"],\"renewOutputType\":\"Quote\"}]}" --target-org target 2>&1 | jq -c '.[0] | {isSuccess, outputValues, errors}')"
sleep 40
q "SELECT QuoteNumber, Name, OriginalActionType, OpportunityId, AccountId, Status, MB_MRR__c, RLM_TermMonths__c, CreatedDate FROM Quote WHERE AccountId = '$acc' AND CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 4" '[.result.records[] | del(.attributes)]'
for id in $(q "SELECT Id FROM Quote WHERE AccountId = '$acc' AND OriginalActionType != null ORDER BY CreatedDate DESC LIMIT 2" '.result.records[].Id' | tr -d '"'); do
  echo "lines $id: $(q "SELECT Product2.ProductCode, Quantity, NetUnitPrice, SalesTransactionActionType__c FROM QuoteLineItem WHERE QuoteId = '$id'" '[.result.records[] | {p: .Product2.ProductCode, qty: .Quantity, net: .NetUnitPrice}]' 2>/dev/null || q "SELECT Product2.ProductCode, Quantity, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '$id'" '[.result.records[] | {p: .Product2.ProductCode, qty: .Quantity, net: .NetUnitPrice}]')"
done
