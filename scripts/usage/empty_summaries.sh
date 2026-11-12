#!/usr/bin/env bash
# Usage test: aggregation (accumulation) policy on the product usage resources and on the test asset
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
echo "== UsageAggregationPolicyId references: $(rest GET /sobjects/ProductUsageResourcePolicy/describe | jq -c '[.fields[] | select(.name=="UsageAggregationPolicyId" or .name=="RatingFrequencyPolicyId") | {name, referenceTo}]')"
echo "== product usage resource policies (QB-DB, CS-25Gb)"
q "SELECT ProductUsageResource.Product.ProductCode, ProductUsageResource.UsageResource.Name, ProductSellingModelId, UsageAggregationPolicyId, RatingFrequencyPolicyId, UsageOveragePolicyId FROM ProductUsageResourcePolicy WHERE ProductUsageResource.Product.ProductCode IN ('QB-DB','CS-25Gb')" | sed 's/"attributes":{[^}]*},//g'
echo "== binding object usage resource policies (all)"
q "SELECT BindingObjectId, UsageResource.Name, UsageAggregationPolicyId, RatingFrequencyPolicyId, EffectiveStartDate FROM BindingObjUsageRsrcPlcy" | sed 's/"attributes":{[^}]*},//g'
echo "== billing (aggregation) policies"
q "SELECT Id, Name, Code, UsageAccumulationMethod, UsageAccumulationPeriod, Status FROM UsageResourceBillingPolicy"
