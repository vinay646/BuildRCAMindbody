#!/usr/bin/env bash
# CHANGES test data only (order 00000111 and its test account): addresses + bill-to contact, activate, then standard asset/contract actions if needed
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
O=$(q "SELECT Id, AccountId FROM Order WHERE OrderNumber = '00000111'" '.result.records[0]'); oid=$(echo $O | jq -r .Id); acc=$(echo $O | jq -r .AccountId)
c=$(q "SELECT Id FROM Contact WHERE AccountId = '$acc' LIMIT 1" '.result.records[0].Id // empty')
[ -z "$c" ] && c=$(sf data create record --sobject Contact --values "LastName='Billing' FirstName='Test' AccountId=$acc Email=test.billing@example.com" --target-org target --json | jq -r .result.id)
A="Street='1 Test St' City='San Luis Obispo' State='CA' PostalCode='93401' Country='United States'"
sf data update record --sobject Order --record-id $oid --values "BillToContactId=$c BillingStreet='1 Test St' BillingCity='San Luis Obispo' BillingState='California' BillingPostalCode='93401' BillingCountry='United States' ShippingStreet='1 Test St' ShippingCity='San Luis Obispo' ShippingState='California' ShippingPostalCode='93401' ShippingCountry='United States'" --target-org target --json | jq -c '{fill: .status, message}'
sf data update record --sobject Order --record-id $oid --values "Status=Activated" --target-org target --json | jq -c '{activate: .status, message}'
sleep 40
echo "order: $(q "SELECT Status, ContractId FROM Order WHERE Id = '$oid'" '.result.records[0] | del(.attributes)')"
echo "auto contracts: $(q "SELECT Id, Status, StartDate, EndDate, ContractTerm FROM Contract WHERE AccountId = '$acc'" '[.result.records[] | del(.attributes)]')"
echo "auto assets: $(q "SELECT Name, Quantity, Status, LifecycleStartDate, LifecycleEndDate FROM Asset WHERE AccountId = '$acc'" '[.result.records[] | del(.attributes)]')"
if [ "$(q "SELECT COUNT() FROM Asset WHERE AccountId = '$acc'" .result.totalSize)" = "0" ]; then
  echo "assets action: $(sf api request rest "$API/actions/standard/createOrUpdateAssetFromOrder" --method POST --body "{\"inputs\":[{\"orderId\":\"$oid\"}]}" --target-org target 2>&1 | jq -c '.[0] | {isSuccess, outputValues, errors}')"
  sleep 30; echo "assets now: $(q "SELECT Name, Quantity, Status, LifecycleStartDate, LifecycleEndDate FROM Asset WHERE AccountId = '$acc'" '[.result.records[] | del(.attributes)]')"
fi
if [ "$(q "SELECT COUNT() FROM Contract WHERE AccountId = '$acc'" .result.totalSize)" = "0" ]; then
  echo "contract action: $(sf api request rest "$API/actions/standard/createContract" --method POST --body "{\"inputs\":[{\"sourceId\":\"$oid\"}]}" --target-org target 2>&1 | jq -c '.[0] | {isSuccess, outputValues, errors}')"
  sleep 15; echo "contracts now: $(q "SELECT Id, Status, StartDate, EndDate, ContractTerm FROM Contract WHERE AccountId = '$acc'" '[.result.records[] | del(.attributes)]')"
  echo "contract lines: $(q "SELECT COUNT() FROM ContractLineItem WHERE ServiceContract.AccountId = '$acc'" .result.totalSize 2>/dev/null)"
fi
