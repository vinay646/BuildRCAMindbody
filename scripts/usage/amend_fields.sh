#!/usr/bin/env bash
# READ ONLY: link fields on the amendment quote / line / asset
sf sobject describe --sobject Quote --target-org target --json | jq -c '[.result.fields[] | select(.type=="reference") | .name]'
sf sobject describe --sobject QuoteLineItem --target-org target --json | jq -c '[.result.fields[] | select(.type=="reference") | .name]'
sf sobject describe --sobject Asset --target-org target --json | jq -c '[.result.fields[] | select(.name|test("Renewal|Contract|Term";"i")) | "\(.name):\(.type):\(.updateable)"]'
id=0Q0hm0000007VK1CAM
sf data query --query "SELECT ContractId, OpportunityId, AccountId, Pricebook2Id, CurrencyIsoCode, LegalEntityId FROM Quote WHERE Id = '$id'" --target-org target --json | jq -c '.result.records[0] | del(.attributes)' 2>&1 | head -c 400; echo
