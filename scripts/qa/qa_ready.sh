#!/usr/bin/env bash
# READ-ONLY sweep of every "Ready for QA" ticket except the Account hierarchy epic (MR-9, MR-10).
set -uo pipefail
API="/services/data/v$ORG_API"
D=$(dirname "$0")
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
run() { echo; echo "################ $1 ($2)"; bash "$D/qa_$2.sh" 2>&1 | cut -c1-3000; }
run "MR-70 MR-71 Catalog" catalog
run "MR-72 Subscription tiers" prd01
run "MR-73 Enterprise" prd02
run "MR-76 Hardware" prd05
run "MR-76 Hardware EU" prd05b
run "MR-78 ERP keys" prd07
run "MR-80 MR-81 MR-82 Bundles" bun01
run "MR-83 Attributes" att01
run "MR-84 Selling models" att02
run "MR-85 Price books" att03
run "MR-86 One plan" cr01
run "MR-87 MR-88 Add-on eligibility" cr03
run "MR-89 Hardware rules" cr07
run "MR-92 MR-95 Term / master contract" cr10
run "MR-93 Region vs price book" cr11
run "MR-96 Payer override" cr14
run "Re-test details" retest
run "Re-test details 2" retest2
echo; echo "################ VALIDATION RULES CHANGED SINCE 14 NOV (full formulas)"
for id in $(sf data query --use-tooling-api --query "SELECT Id FROM ValidationRule WHERE LastModifiedDate >= 2026-11-14T00:00:00Z" --target-org target --json | jq -r '.result.records[].Id'); do
  sf api request rest "$API/tooling/sobjects/ValidationRule/$id" --target-org target | jq -c '{obj: .EntityDefinitionId, name: .ValidationName, active: .Metadata.active, modified: .LastModifiedDate, by: .LastModifiedById, formula: .Metadata.errorConditionFormula, field: .Metadata.errorDisplayField, msg: .Metadata.errorMessage}'
done
echo; echo "################ FLOWS CHANGED SINCE 16 NOV"
sf data query --use-tooling-api --query "SELECT DeveloperName, ActiveVersion.VersionNumber, LatestVersion.VersionNumber, LastModifiedDate, LastModifiedBy.Name FROM FlowDefinition WHERE LastModifiedDate >= 2026-11-16T00:00:00Z" --target-org target --json | jq -c '.result.records[] | {n: .DeveloperName, active: .ActiveVersion.VersionNumber, latest: .LatestVersion.VersionNumber, at: .LastModifiedDate, by: .LastModifiedBy.Name}'
for name in $(sf data query --use-tooling-api --query "SELECT DeveloperName FROM FlowDefinition WHERE LastModifiedDate >= 2026-11-16T00:00:00Z" --target-org target --json | jq -r '.result.records[].DeveloperName'); do
  id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = '$name' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty')
  [ -z "$id" ] && { echo "== FLOW $name: no active version"; continue; }
  echo "== FLOW $name"
  sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target | jq -c 'def v: (.stringValue // .numberValue // (if .booleanValue == null then null else (.booleanValue|tostring) end) // .elementReference); .Metadata | {object: .start.object, type: .start.triggerType, when: .start.recordTriggerType, filters: [.start.filters[]? | "\(.field) \(.operator) \(.value|v)"], lookups: [.recordLookups[]? | {name, object, filters: [.filters[]? | "\(.field) \(.operator) \(.value|v)"]}], decisions: [.decisions[]? | {name, rules: [.rules[]? | {logic: .conditionLogic, conds: [.conditions[]? | "\(.leftValueReference) \(.operator) \(.rightValue|v)"]}]}], formulas: [.formulas[]? | {name, expression}], errors: [.customErrors[]? | [.customErrorMessages[]? | .errorMessage] | join(" ")]}' | cut -c1-4000
done
echo; echo "################ MR-12 Tier bundles (US-05)"
echo "== SMS allowance attribute / fields"; raw "SELECT Product2.ProductCode, AttributeDefinition.Name, DefaultValue FROM ProductAttributeDefinition WHERE AttributeDefinition.Name LIKE '%SMS%'"
for o in Product2 QuoteLineItem Asset; do echo "$o $(sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.name|test("SMS|Allowance";"i")) | .name]')"; done
echo "== Enterprise components (Branded App default selection)"; raw "SELECT ParentProduct.ProductCode, ChildProduct.ProductCode, IsComponentRequired, IsDefaultComponent, DoesBundlePriceIncludeChild, Quantity FROM ProductRelatedComponent WHERE ParentProduct.ProductCode = 'MB-ENT'"
echo "== Tier display order"; raw "SELECT ProductCode, Name, DisplayUrl, StockKeepingUnit FROM Product2 WHERE ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT')"
raw "SELECT Product.ProductCode, Catalog.Name, ProductCategory.Name, SortOrder FROM ProductCategoryProduct WHERE Product.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT')"
echo "== Sales price editability (field permissions on QuoteLineItem.UnitPrice)"; raw "SELECT Parent.Profile.Name, Parent.Label, PermissionsEdit FROM FieldPermissions WHERE SobjectType = 'QuoteLineItem' AND Field = 'QuoteLineItem.UnitPrice'"
echo "################ MR-27 Enterprise configurable bundle"
raw "SELECT ProductCode, Name, Type, ConfigureDuringSale, IsActive FROM Product2 WHERE ProductCode = 'MB-ENT'"
raw "SELECT Name, MinBundleComponents, MaxBundleComponents FROM ProductComponentGroup WHERE ParentProduct.ProductCode = 'MB-ENT'"
