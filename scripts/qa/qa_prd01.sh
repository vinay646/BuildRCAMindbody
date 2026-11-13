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
raw "SELECT Product.ProductCode, AttributeDefinition.Name, DefaultValue, IsReadOnly FROM ProductAttributeDefinition WHERE Product.ProductCode IN ('MB-ULT','MB-F-MKTG')"
echo "== VALIDATION RULES (term / frequency)"; raw "SELECT EntityDefinition.QualifiedApiName, ValidationName, Active, ErrorMessage FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Quote','QuoteLineItem','OrderItem')" "--use-tooling-api"
echo "== CONSTRAINT / CONFIG RULES mentioning term"; raw "SELECT Name, Status FROM ExpressionSetDefinition WHERE Name LIKE '%Term%' OR Name LIKE '%Frequen%' OR Name LIKE '%CR-13%'" 
