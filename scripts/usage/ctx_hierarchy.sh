#!/usr/bin/env bash
# Node names of the standard CartDetailGetEligiblePromotion context; is a category hierarchy node present?
set -uo pipefail
API="/services/data/v$ORG_API"
D=$(sf api request rest "$API/connect/context-definitions/CartDetailGetEligiblePromotion__stdctx" --target-org target 2>&1)
echo "BYTES $(echo "$D" | wc -c)"
echo "ANY 'ierarch' TEXT: $(echo "$D" | grep -o '[A-Za-z_/]*[Hh]ierarch[A-Za-z_]*' | sort -u | tr '\n' ' ')"
echo "NODES $(echo "$D" | jq -c '[.. | objects | select(has("contextNodeId")) | .contextNodeId | split("/") | last] | unique')"
echo "CATEGORY ATTRS $(echo "$D" | jq -c '[.. | objects | select(has("contextAttributeId")) | .contextAttributeId | select(test("ategor"))] | unique')"
