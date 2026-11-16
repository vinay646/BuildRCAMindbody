#!/usr/bin/env bash
# READ-ONLY: details for the re-test (Enterprise prices, new flows, field permissions).
set -uo pipefail
API="/services/data/v$ORG_API"
echo "== PRICE BOOKS"; sf data query --query "SELECT Name, IsActive, IsStandard FROM Pricebook2" --target-org target --json | jq -c '[.result.records[] | "\(.Name) \(if .IsActive then "active" else "INACTIVE" end)"]'
echo "== ENT PRICES"; sf data query --query "SELECT Pricebook2.Name, CurrencyIsoCode, UnitPrice, ProductSellingModel.Name, IsActive FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ENT' ORDER BY Pricebook2.Name, CurrencyIsoCode" --target-org target --json | jq -r '.result.records[] | "\(.Pricebook2.Name) | \(.CurrencyIsoCode) \(.UnitPrice) | \(.ProductSellingModel.Name) | active=\(.IsActive)"'
echo "== FLS EDIT"; sf data query --query "SELECT Field, Parent.Label, Parent.Profile.Name FROM FieldPermissions WHERE SobjectType = 'Product2' AND Field IN ('Product2.ERP_ID__c','Product2.Integration_Status__c') AND PermissionsEdit = true" --target-org target --json | jq -c '[.result.records[] | "\(.Field): \(.Parent.Profile.Name // .Parent.Label)"]'
for f in Starter_product_Billing_Frequency_Validation Validation_QLE_Check_Master_Contract_for_Enterprise_Products Quote_Enterprise_Product_Term_Validation; do
  id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = '$f' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty')
  echo "== FLOW $f"
  sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target | jq -c 'def v: (.stringValue // .numberValue // (if .booleanValue == null then null else (.booleanValue|tostring) end) // .elementReference); .Metadata | {object: .start.object, type: .start.triggerType, when: .start.recordTriggerType, filters: [.start.filters[]? | "\(.field) \(.operator) \(.value|v)"], lookups: [.recordLookups[]? | {name, object, filterLogic, filters: [.filters[]? | "\(.field) \(.operator) \(.value|v)"]}], decisions: [.decisions[]? | {name, rules: [.rules[]? | {logic: .conditionLogic, conds: [.conditions[]? | "\(.leftValueReference) \(.operator) \(.rightValue|v)"]}]}], errors: [.customErrors[]? | [.customErrorMessages[]? | .errorMessage] | join(" ")]}'
done
