#!/usr/bin/env bash
# READ-ONLY QA for MB-PRD-01 Subscription tiers Starter, Accelerate, Ultimate.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes) | with_entries(select(.value != null and (.key|test("^(IsDeleted|SystemModstamp|LastViewedDate|LastReferencedDate|LastModifiedById|CreatedById|OwnerId|CreatedDate|LastModifiedDate)$")|not)))] else {error: .message} end'; }
T="('MB-STR','MB-ACC','MB-ULT')"
echo "== TIER PRODUCTS"; raw "SELECT FIELDS(ALL) FROM Product2 WHERE ProductCode IN $T LIMIT 10"
echo "== UNIT OF MEASURE"; raw "SELECT ProductCode, QuantityUnitOfMeasure, UnitOfMeasureId, UnitOfMeasure.Name FROM Product2 WHERE ProductCode IN $T"
echo "== SELLING MODEL OPTIONS"; raw "SELECT Product2.ProductCode, ProductSellingModel.Name, ProductSellingModel.SellingModelType, ProductSellingModel.PricingTerm, ProductSellingModel.PricingTermUnit, IsDefault FROM ProductSellingModelOption WHERE Product2.ProductCode IN $T"
echo "== PRICE BOOK ENTRIES"; raw "SELECT Product2.ProductCode, Pricebook2.Name, Pricebook2.IsStandard, CurrencyIsoCode, UnitPrice, ProductSellingModel.Name, IsActive FROM PricebookEntry WHERE Product2.ProductCode IN $T ORDER BY Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode"
echo "== PRODUCT CUSTOM FIELDS (term / frequency)"; sf api request rest "$API/sobjects/Product2/describe" --target-org target | jq -c '[.fields[] | select(.custom) | {name, label, type, picklist: ([.picklistValues[]?.value] | if length>0 then . else null end)}]'
echo "== ULTIMATE SMS: usage resources and grants"; raw "SELECT Product.ProductCode, UsageResource.Name, Status FROM ProductUsageResource WHERE Product.ProductCode IN $T"
raw "SELECT ProductId, Product.ProductCode, Label, Quantity, UnitOfMeasure.Name, ValidityPeriodTerm, ValidityPeriodUnit, UsageRsrc.Name, Status, Type FROM ProductUsageGrant WHERE Product.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-F-MKTG','MB-SMS') OR UsageDefinitionProduct.ProductCode IN ('MB-ULT','MB-F-MKTG','MB-SMS')"
echo "== ULTIMATE SMS: components and attributes"; raw "SELECT ParentProduct.ProductCode, ChildProduct.ProductCode, ChildProduct.Name, Quantity FROM ProductRelatedComponent WHERE ParentProduct.ProductCode = 'MB-ULT' AND (ChildProduct.ProductCode LIKE '%SMS%' OR ChildProduct.ProductCode LIKE '%MKTG%' OR ChildProduct.Name LIKE '%SMS%' OR ChildProduct.Name LIKE '%Text%')"
raw "SELECT FIELDS(ALL) FROM ProductAttributeDefinition WHERE Product2Id IN (SELECT Id FROM Product2 WHERE ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-F-MKTG','MB-SMS')) LIMIT 200"
echo "== CLASSIFICATION ATTRIBUTES"; raw "SELECT FIELDS(ALL) FROM ProductClassificationAttr WHERE ProductClassificationId IN (SELECT BasedOnId FROM Product2 WHERE ProductCode IN ('MB-F-MKTG','MB-SMS')) LIMIT 200"
echo "== ATTRIBUTE DEFINITIONS"; raw "SELECT Id, Name, Code, DataType, DefaultValue FROM AttributeDefinition LIMIT 200"
echo "== VALIDATION RULES (term / frequency)"; raw "SELECT EntityDefinition.QualifiedApiName, ValidationName, Active, ErrorMessage FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Quote','QuoteLineItem','OrderItem')" "--use-tooling-api"
echo "== QUOTE LINE TERM / FREQUENCY PICKLISTS"; sf api request rest "$API/sobjects/QuoteLineItem/describe" --target-org target | jq -c '[.fields[] | select(.name|test("BillingFrequency|SubscriptionTerm|Term";"i")) | {name, type, picklist: [.picklistValues[]?.value]}]'
echo "== CONSTRAINT MODELS"; raw "SELECT Id, ApiName, Name, Status FROM ExpressionSet WHERE UsageType = 'Constraint'"
echo "== CML TEXT (term / frequency lines)"; for id in $(sf data query --query "SELECT Id FROM ExpressionSetVersion WHERE ExpressionSet.UsageType = 'Constraint' AND IsActive = true" --target-org target --json | jq -r '.result.records[]?.Id'); do sf api request rest "$API/connect/cml/expression-set-versions/$id" --target-org target 2>/dev/null | tr ',;' '\n\n' | grep -i -E "term|frequen|MB-STR|Starter" | head -20; done
