#!/usr/bin/env bash
# READ-ONLY QA for MR-78 MB-PRD-07 ERP keys and integration status.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
for o in Product2 Account; do
  echo "== $o fields"
  sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.name|test("ERP|Integration_Status|Billing_ID";"i")) | {n: .name, l: .label, t: .type, unique: .unique, extId: .externalId, default: (.defaultValue // null), values: [.picklistValues[]?.value]}]'
done
echo "== MB- products by integration status"
q "SELECT Integration_Status__c s, COUNT(Id) n FROM Product2 WHERE ProductCode LIKE 'MB-%' GROUP BY Integration_Status__c"
q "SELECT ProductCode, Integration_Status__c, ERP_ID__c FROM Product2 WHERE ProductCode LIKE 'MB-%' AND (Integration_Status__c != 'New' OR Integration_Status__c = null)"
echo "== who can edit ERP ID / Integration Status on Product2"
q "SELECT Field, Parent.Label, Parent.Profile.Name, PermissionsEdit FROM FieldPermissions WHERE SobjectType = 'Product2' AND Field IN ('Product2.ERP_ID__c','Product2.Integration_Status__c') AND PermissionsEdit = true" | jq -r '.[] | "   \(.Field) | \(.Parent.Profile.Name // .Parent.Label)"'
echo "== validation rules on these fields"
sf data query --use-tooling-api --query "SELECT EntityDefinition.QualifiedApiName, ValidationName, Active FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Product2','Account')" --target-org target --json | jq -r '.result.records[] | "   \(.EntityDefinition.QualifiedApiName).\(.ValidationName) active=\(.Active)"'
