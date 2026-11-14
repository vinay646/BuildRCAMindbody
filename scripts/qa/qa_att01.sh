#!/usr/bin/env bash
# READ-ONLY QA for MB-ATT-01 Product attributes and main key fields.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
for o in Account Opportunity Quote; do
  echo "== $o FIELDS"; sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.custom and (.name|test("Vertical|Region|Location|Prior";"i"))) | {name, label, type, picklist: [.picklistValues[]? | select(.active) | .value]}]'
done
echo "== ATTRIBUTE DEFINITIONS"; raw "SELECT Id, Name, DataType, DefaultValue, PicklistId, Picklist.Name FROM AttributeDefinition WHERE Name IN ('Payments Opted In','Card-Present','Card Present','Branded App Platform','SMS Allowance')"
echo "== PICKLIST VALUES"; raw "SELECT Picklist.Name, Name, Value, Status FROM AttributePicklistValue WHERE Picklist.Name != null ORDER BY Picklist.Name" 
echo "== PRODUCT ATTRIBUTES (direct)"; raw "SELECT Product2.ProductCode, AttributeDefinition.Name, DefaultValue, IsRequired, IsHidden FROM ProductAttributeDefinition WHERE Product2.ProductCode LIKE 'MB-%'"
echo "== CLASSIFICATION ATTRIBUTES"; raw "SELECT ProductClassification.Name, AttributeDefinition.Name, DefaultValue, IsRequired FROM ProductClassificationAttr WHERE AttributeDefinition.Name IN ('Payments Opted In','Card-Present','Card Present','Branded App Platform','SMS Allowance','Vertical','Region','Location count','Prior System')"
echo "== PRODUCT CLASSIFICATIONS"; raw "SELECT ProductCode, BasedOn.Name FROM Product2 WHERE ProductCode IN ('MB-PAY','MB-APP','MB-F-MKTG','MB-SMS')"
