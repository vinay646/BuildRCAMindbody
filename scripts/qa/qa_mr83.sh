#!/usr/bin/env bash
# READ-ONLY QA for MR-83 MB-ATT-01 Product attributes and main key fields.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
d() { sf api request rest "$API/sobjects/$1/describe" --target-org target | jq -c --arg r "$2" '[.fields[] | select(.name|test($r;"i")) | {n: .name, l: .label, t: .type, f: (.calculatedFormula // null), values: [.picklistValues[]? | select(.active) | .value]}]'; }
echo "== Account Vertical / Region";  d Account '^Vertical__c$|^Region__c$'
echo "== Opportunity Location Count / Prior System"; d Opportunity 'Location|Prior'
echo "== Quote Prior System / Location"; d Quote 'Prior|Location'
echo "== product attributes (classification attributes)"
q "SELECT ProductClassification.Name, Name, AttributeDefinition.DataType, AttributeDefinition.PicklistId, DefaultValue, Status FROM ProductClassificationAttr WHERE Name IN ('Payments Opted In','Branded App Platform','SMS Allowance','Card Present')" | jq -r '.[] | "   \(.ProductClassification.Name) | \(.Name) | \(.AttributeDefinition.DataType) | default=\(.DefaultValue) | \(.Status)"'
echo "== attribute picklist values"
q "SELECT Name, (SELECT Value, Status FROM AttributePicklistValues) FROM AttributePicklist WHERE Name LIKE '%Opt%' OR Name LIKE '%Platform%' OR Name LIKE '%Card%' OR Name LIKE '%Yes%'" | jq -c '.[] | {n: .Name, v: [.AttributePicklistValues.records[]?.Value]}'
q "SELECT Id, Name, DataType, PicklistId, Picklist.Name FROM AttributeDefinition WHERE Name IN ('Payments Opted In','Branded App Platform','SMS Allowance','Card Present')"
echo "== which products carry those classifications"
q "SELECT ProductCode, Name, BasedOn.Name FROM Product2 WHERE BasedOnId IN (SELECT ProductClassificationId FROM ProductClassificationAttr WHERE Name IN ('Payments Opted In','Branded App Platform','SMS Allowance','Card Present'))" | jq -r '.[] | "   \(.ProductCode) | \(.Name) | \(.BasedOn.Name)"'
