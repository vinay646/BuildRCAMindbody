#!/usr/bin/env bash
# READ ONLY: opportunity products created by quote sync – any field linking them to the quote line?
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
sf sobject describe --sobject OpportunityLineItem --target-org target --json | jq -c '[.result.fields[] | select(.type=="reference" or (.name|test("Sync|Quote";"i"))) | .name]'
opp=$(q "SELECT Id FROM Opportunity WHERE SyncedQuoteId != null AND Name LIKE 'MR103%' ORDER BY CreatedDate DESC LIMIT 1" '.result.records[0].Id' | tr -d '"')
f=$(sf sobject describe --sobject OpportunityLineItem --target-org target --json | jq -r '[.result.fields[] | select(.type=="reference" or (.name|test("Sync|Quote";"i"))) | .name] | join(",")')
q "SELECT $f FROM OpportunityLineItem WHERE OpportunityId = '$opp' LIMIT 2" '[.result.records[] | del(.attributes)]'
echo "opp ContractId field: $(sf sobject describe --sobject Opportunity --target-org target --json | jq -c '[.result.fields[] | select(.name=="ContractId") | .updateable]')"
