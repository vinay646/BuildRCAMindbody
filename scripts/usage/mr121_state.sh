#!/usr/bin/env bash
# READ ONLY: MR-121 3.10-3.15 current state on the Q2C04 test account
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
acc=$(q "SELECT Id FROM Account WHERE Name LIKE 'MR103 Q2C04%' LIMIT 1" '.result.records[0].Id' | tr -d '"')
echo "account: $(q "SELECT Active_Location_Count__c, Root_Account__c FROM Account WHERE Id = '$acc'" '.result.records[0] | del(.attributes)')"
sf sobject describe --sobject Account --target-org target --json | jq -c '.result.fields[] | select(.name=="Active_Location_Count__c") | {type, calculated, calculatedFormula}'
echo "location-count automation: $(q "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName LIKE '%Location%' OR ApiName LIKE '%Hierarchy%'" '[.result.records[] | "\(.ApiName):\(.IsActive)"]') | classes: $(sf data query --use-tooling-api --query "SELECT Name FROM ApexClass WHERE Name LIKE '%Location%' OR Name LIKE '%Hierarchy%'" --target-org target --json | jq -c '[.result.records[].Name]')"
echo "billing schedules: $(q "SELECT COUNT() FROM BillingSchedule WHERE ReferenceEntity.Name != null AND CreatedDate = TODAY" .result.totalSize 2>/dev/null) | by order: $(q "SELECT ReferenceEntityId, Status, COUNT(Id) n FROM BillingSchedule GROUP BY ReferenceEntityId, Status LIMIT 5" '[.result.records[] | del(.attributes)]' 2>&1 | head -c 300)"
echo "order 113 items -> billing: $(q "SELECT Id FROM Order WHERE OrderNumber = '00000113'" '.result.records[0].Id')"
echo "asset fields: $(sf sobject describe --sobject Asset --target-org target --json | jq -c '[.result.fields[] | select(.name|test("Type|Usage|Lifecycle|Renew|Product2|Contract";"i")) | .name]')"
echo "event objects: $(sf sobject list --target-org target 2>/dev/null | grep -i "__e$" | tr '\n' ' ')"
echo "permsets: $(q "SELECT Name, Label FROM PermissionSet WHERE IsOwnedByProfile = false AND (Name LIKE 'MB%' OR Name LIKE '%Order%' OR Name LIKE '%Sales%')" '[.result.records[] | .Name]')"
echo "queues/groups: $(q "SELECT DeveloperName, Type FROM Group WHERE DeveloperName LIKE 'MB%'" '[.result.records[] | "\(.DeveloperName):\(.Type)"]')"
