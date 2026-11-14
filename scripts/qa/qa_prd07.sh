#!/usr/bin/env bash
# READ-ONLY QA for MB-PRD-07 ERP keys and integration status on products.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
echo "== PRODUCT FIELDS"; sf api request rest "$API/sobjects/Product2/describe" --target-org target | jq -c '[.fields[] | select(.name|test("ERP|Integration";"i")) | {name, label, type, length, defaultValue: (.defaultValueFormula // .defaultValue), picklist: [.picklistValues[]? | {value, default: .defaultValue}], updateable, externalId, unique}]'
echo "== MB PRODUCT VALUES"; raw "SELECT ProductCode, ERP_ID__c, Integration_Status__c FROM Product2 WHERE ProductCode LIKE 'MB-%' ORDER BY ProductCode"
echo "== FIELD PERMISSIONS"; raw "SELECT Parent.Label, Parent.IsOwnedByProfile, Parent.Profile.Name, Field, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE SobjectType = 'Product2' AND Field IN ('Product2.ERP_ID__c','Product2.Integration_Status__c')"
echo "== AUTOMATION ON PRODUCT"; raw "SELECT ApiName, Label, TriggerType FROM FlowDefinitionView WHERE IsActive = true AND TriggerObjectOrEventLabel = 'Product'"
