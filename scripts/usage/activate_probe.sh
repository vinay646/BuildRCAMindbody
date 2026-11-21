#!/usr/bin/env bash
# CHANGES test order 00000111 only: activate it, then show what the platform created (contract, assets)
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
O=$(q "SELECT Id, AccountId FROM Order WHERE OrderNumber = '00000111'" '.result.records[0]'); oid=$(echo $O | jq -r .Id); acc=$(echo $O | jq -r .AccountId)
echo "before: contracts $(q "SELECT COUNT() FROM Contract WHERE AccountId = '$acc'" .result.totalSize), assets $(q "SELECT COUNT() FROM Asset WHERE AccountId = '$acc'" .result.totalSize)"
sf data update record --sobject Order --record-id $oid --values "Status=Activated" --target-org target --json | jq -c '{status, message}'
sleep 40
echo "order: $(q "SELECT Status, ContractId, ActivatedDate FROM Order WHERE Id = '$oid'" '.result.records[0] | del(.attributes)')"
echo "contracts: $(q "SELECT Id, Status, StartDate, EndDate, ContractTerm FROM Contract WHERE AccountId = '$acc'" '[.result.records[] | del(.attributes)]')"
echo "assets: $(q "SELECT Name, Quantity, Status, ContractId__c FROM Asset WHERE AccountId = '$acc'" '[.result.records[] | del(.attributes)]' 2>/dev/null || q "SELECT Name, Quantity, Status FROM Asset WHERE AccountId = '$acc'" '[.result.records[] | del(.attributes)]')"
echo "assets(basic): $(q "SELECT Name, Quantity, Status, CurrentQuantity, LifecycleStartDate, LifecycleEndDate FROM Asset WHERE AccountId = '$acc'" '[.result.records[] | del(.attributes)]')"
