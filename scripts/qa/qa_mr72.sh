#!/usr/bin/env bash
# READ-ONLY QA for MR-72 MB-PRD-01 Subscription tiers.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== tiers: unit of measure and custom term / frequency fields"
fields=$(sf api request rest "$API/sobjects/Product2/describe" --target-org target | jq -r '[.fields[] | select(.custom and (.name|test("term|freq";"i"))) | .name] | join(",")')
echo "   Product2 term/frequency fields: $fields"
q "SELECT ProductCode, QuantityUnitOfMeasure${fields:+, $fields} FROM Product2 WHERE ProductCode IN ('MB-STR','MB-ACC','MB-ULT')"
echo "== selling model options"
q "SELECT Product2.ProductCode, ProductSellingModel.Name, IsDefault FROM ProductSellingModelOption WHERE Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT') ORDER BY Product2.ProductCode" | jq -r '.[] | "   \(.Product2.ProductCode) | \(.ProductSellingModel.Name) | default=\(.IsDefault)"'
echo "== prices (regional books)"
q "SELECT Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode, ProductSellingModel.Name, UnitPrice FROM PricebookEntry WHERE Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT') AND Pricebook2.IsStandard = false AND IsActive = true ORDER BY Product2.ProductCode, CurrencyIsoCode" | jq -r '.[] | "   \(.Product2.ProductCode) | \(.CurrencyIsoCode) | \(.ProductSellingModel.Name) | \(.UnitPrice)"'
echo "== quote term field"
sf api request rest "$API/sobjects/Quote/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Term";"i")) | {n: .name, t: .type, values: [.picklistValues[]?.value]}]'
echo "== rules on term / billing frequency (flows and validation rules)"
for f in Starter_product_Billing_Frequency_Validation Quote_Term_and_Account_s_Master_Contract_Validation; do
  id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = '$f' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty')
  echo "   $f active=$([ -n "$id" ] && echo yes || echo no)"
done
sf data query --use-tooling-api --query "SELECT EntityDefinition.QualifiedApiName, ValidationName, Active FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Quote','QuoteLineItem')" --target-org target --json | jq -r '.result.records[] | "   VR \(.EntityDefinition.QualifiedApiName).\(.ValidationName) active=\(.Active)"'
echo "== quote lines on tiers by term and frequency (what has been saved)"
q "SELECT Product2.ProductCode p, Quote.RLM_TermMonths__c t, BillingFrequency f, COUNT(Id) n FROM QuoteLineItem WHERE Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT') GROUP BY Product2.ProductCode, Quote.RLM_TermMonths__c, BillingFrequency"
echo "== Ultimate 1,000 texts: usage grants, attributes"
q "SELECT Product.ProductCode, Label, Quantity, UnitOfMeasure.Name, ValidityPeriodTerm, ValidityPeriodUnit, Status, Type, UsageRsrc.Name FROM ProductUsageGrant"
q "SELECT ProductCode, Name FROM Product2 WHERE Id IN (SELECT ProductId FROM ProductUsageGrant)" 2>/dev/null
q "SELECT Product2.ProductCode, AttributeDefinition.Name, DefaultValue FROM ProductAttributeDefinition WHERE AttributeDefinition.Name LIKE '%SMS%'"
q "SELECT Name, ProductClassification.Name, IsHidden, IsReadOnly, Status FROM ProductClassificationAttr WHERE Name LIKE '%SMS%'"
q "SELECT ProductCode, BasedOn.Name FROM Product2 WHERE ProductCode IN ('MB-STR','MB-ACC','MB-ULT')"
