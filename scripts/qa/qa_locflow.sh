#!/usr/bin/env bash
# READ-ONLY: Location Count flow filter logic and actual values.
set -uo pipefail
API="/services/data/v$ORG_API"
id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = 'Update_Opportunity_Location_Count' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id')
sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target | jq -c '.Metadata | {lookups: [.recordLookups[] | {name, filterLogic, filters: [.filters[] | "\(.field) \(.operator) \(.value.stringValue // .value.elementReference)"]}], order: [.recordLookups[], .loops[], .assignments[], .decisions[], .recordUpdates[] | {name, next: (.connector.targetReference // .nextValueConnector.targetReference // .defaultConnector.targetReference), noMore: .noMoreValuesConnector.targetReference}]}'
echo "== OPP LOCATION COUNTS"; sf data query --query "SELECT Name, Account.Name, Account.Root_Account__c, Location_count__c, CreatedDate FROM Opportunity WHERE CreatedDate >= 2026-11-12T00:00:00Z ORDER BY CreatedDate DESC LIMIT 15" --target-org target --json | jq -c '[.result.records[] | {n: .Name, acc: .Account.Name, loc: .Location_count__c, at: .CreatedDate[0:16]}]'
echo "== TIER ASSETS"; sf data query --query "SELECT Product2.ProductCode, COUNT(Id) n FROM Asset WHERE Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT') GROUP BY Product2.ProductCode" --target-org target --json | jq -c '[.result.records[] | del(.attributes)]'
