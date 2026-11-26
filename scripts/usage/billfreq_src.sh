#!/usr/bin/env bash
# Read-only: where quote lines get Billing Frequency - product/PSM option defaults for MB-ACC and a feature, and flows on QuoteLineItem that set BillingFrequency
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
for c in MB-ACC MB-F-POS; do
  echo "$c PRODUCT $(sf data query --query "SELECT FIELDS(ALL) FROM Product2 WHERE ProductCode = '$c' LIMIT 1" --target-org target --json 2>/dev/null | jq -c '.result.records[0] | with_entries(select((.key|test("Billing|Frequen|Term|Selling";"i")) and .value != null))')"
  echo "$c PSMO $(sf data query --query "SELECT FIELDS(ALL) FROM ProductSellingModelOption WHERE Product2.ProductCode = '$c' LIMIT 3" --target-org target --json 2>/dev/null | jq -c '[.result.records[] | with_entries(select((.key|test("Billing|Frequen|Term|Default|SellingModel";"i")) and .value != null))]')"
done
echo "ATTR BILLING FREQ $(q "SELECT Name, DataType FROM AttributeDefinition WHERE Name LIKE '%requenc%'")"
t() { sf data query --use-tooling-api --query "$1" --target-org target --json 2>/dev/null; }
for id in $(sf data query --query "SELECT ActiveVersionId FROM FlowDefinitionView WHERE IsActive = true AND ProcessType = 'AutoLaunchedFlow' AND TriggerObjectOrEventLabel = 'Quote Line Item'" --target-org target --json 2>/dev/null | jq -r '.result.records[].ActiveVersionId'); do
  t "SELECT Definition.DeveloperName, Metadata FROM Flow WHERE Id = '$id'" | jq -r '.result.records[0] | select((.Metadata|tostring)|test("BillingFrequency")) | "FLOW SETS FREQ: \(.Definition.DeveloperName) \(.Metadata.start.triggerType) \(.Metadata.start.recordTriggerType)"'
done
