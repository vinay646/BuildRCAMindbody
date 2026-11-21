#!/usr/bin/env bash
# CHANGES order 00000115 (user's test order): retries the activation steps and prints each error
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
id=$(q "SELECT Id FROM Order WHERE OrderNumber = '00000115'" '.result.records[0].Id' | tr -d '"')
echo "quote: $(q "SELECT Quote.QuoteNumber, Quote.OriginalActionType, Quote.Opportunity.Type FROM Order WHERE Id = '$id'" '.result.records[0].Quote | {QuoteNumber, OriginalActionType, opp: .Opportunity.Type}')"
echo "items: $(q "SELECT Product2.ProductCode, Quantity, OrderActionId FROM OrderItem WHERE OrderId = '$id'" '[.result.records[] | {p: .Product2.ProductCode, q: .Quantity}]')"
c=$(q "SELECT Id FROM Contract WHERE AccountId IN (SELECT AccountId FROM Order WHERE Id = '$id') AND Status = 'Activated' LIMIT 1" '.result.records[0].Id' | tr -d '"')
echo "error field: $(sf data update record --sobject Order --record-id $id --values "MB_Activation_Error__c='test'" --target-org target --json | jq -c '{status, message}')"
echo "co-term: $(sf data update record --sobject Order --record-id $id --values "ContractId=$c" --target-org target --json | jq -c '{status, message}')"
echo "activate: $(sf data update record --sobject Order --record-id $id --values "Status=Activated MB_Activation_Error__c=''" --target-org target --json | jq -c '{status, message}')"
echo "now: $(q "SELECT Status, ContractId FROM Order WHERE Id = '$id'" '.result.records[0] | del(.attributes)')"
