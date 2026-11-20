#!/usr/bin/env bash
# READ-ONLY: attributes on the Email and SMS Marketing feature product (MB-F-MKTG) and where it sits.
set -uo pipefail
q() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== product"
q "SELECT Id, ProductCode, Name, Type, BasedOnId, BasedOn.Name, BasedOn.Code, QuantityUnitOfMeasure, IsActive FROM Product2 WHERE ProductCode = 'MB-F-MKTG' OR Name LIKE '%SMS Marketing%'"
echo "== attributes defined directly on the product (ProductAttributeDefinition)"
q "SELECT Product2.ProductCode, AttributeDefinition.Name, AttributeDefinition.Code, AttributeDefinition.DataType, DefaultValue, IsRequired, IsHidden, IsReadOnly, IsPriceImpacting, Status, AttributeNameOverride, ProductClassificationAttribute.Name FROM ProductAttributeDefinition WHERE Product2.ProductCode = 'MB-F-MKTG'"
echo "== attributes inherited from its classification"
q "SELECT ProductClassification.Name, Name, AttributeDefinition.Name, AttributeDefinition.DataType, DefaultValue, IsRequired, IsHidden, IsReadOnly, IsPriceImpacting, Status FROM ProductClassificationAttr WHERE ProductClassificationId IN (SELECT BasedOnId FROM Product2 WHERE ProductCode = 'MB-F-MKTG')"
echo "== every SMS attribute (definition, classification attribute, product attribute)"
q "SELECT Id, Name, Code, DataType, DefaultValue, Status, Description FROM AttributeDefinition WHERE Name LIKE '%SMS%' OR Name LIKE '%Text%' OR Name LIKE '%Allowance%'"
q "SELECT ProductClassification.Name, ProductClassification.Code, Name, DefaultValue, Status FROM ProductClassificationAttr WHERE Name LIKE '%SMS%'"
q "SELECT Product2.ProductCode, Product2.Name, AttributeDefinition.Name, DefaultValue FROM ProductAttributeDefinition WHERE AttributeDefinition.Name LIKE '%SMS%'"
echo "== which products use the classifications that carry SMS Allowance"
q "SELECT ProductCode, Name, BasedOn.Name FROM Product2 WHERE BasedOnId IN (SELECT ProductClassificationId FROM ProductClassificationAttr WHERE Name LIKE '%SMS%')"
echo "== bundles that include MB-F-MKTG"
q "SELECT ParentProduct.ProductCode, ProductComponentGroup.Name, Quantity, QuantityScaleMethod, IsComponentRequired, IsDefaultComponent FROM ProductRelatedComponent WHERE ChildProduct.ProductCode = 'MB-F-MKTG'"
echo "== usage grants / resources on MB-F-MKTG, MB-ULT, MB-SMS"
q "SELECT Product.ProductCode, Label, Quantity, UnitOfMeasure.Name, ValidityPeriodTerm, ValidityPeriodUnit, Status, Type, UsageRsrc.Name, RenewalPolicy FROM ProductUsageGrant WHERE Product.ProductCode IN ('MB-F-MKTG','MB-ULT','MB-SMS')"
q "SELECT Product.ProductCode, UsageResource.Name, Status FROM ProductUsageResource WHERE Product.ProductCode IN ('MB-F-MKTG','MB-ULT','MB-SMS')"
echo "== attribute values on recent Ultimate quotes (QuoteLineItemAttribute)"
q "SELECT QuoteLineItem.Quote.QuoteNumber, QuoteLineItem.Product2.ProductCode, AttributeDefinition.Name, AttributeValue FROM QuoteLineItemAttribute WHERE AttributeDefinition.Name LIKE '%SMS%' ORDER BY CreatedDate DESC LIMIT 10"
