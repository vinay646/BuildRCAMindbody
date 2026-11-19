#!/usr/bin/env bash
# READ ONLY: full flow/trigger detail of the debug logs between FROM and TO (UTC), filtered.
set -uo pipefail
FROM=${FROM:-2026-11-19T11:37:40Z}; TO=${TO:-2026-11-19T11:37:50Z}
for id in $(sf data query --use-tooling-api --query "SELECT Id FROM ApexLog WHERE StartTime >= $FROM AND StartTime <= $TO ORDER BY StartTime" --target-org target --json | jq -r '.result.records[].Id'); do
  body=$(sf api request rest "/services/data/v$ORG_API/tooling/sobjects/ApexLog/$id/Body" --target-org target 2>/dev/null)
  echo "===== log $id"
  echo "$body" | grep -iE "coupon|FLOW_START_INTERVIEWS_BEGIN|FLOW_CREATE_INTERVIEW|FLOW_VALUE_ASSIGNMENT.*Coupon|FLOW_RULE|FLOW_START_SCHEDULED|DML_BEGIN|EXCEPTION|FATAL|VALIDATION_FAIL|FLOW_ELEMENT_ERROR|Flow:QuoteLineItem" | sed -E 's/^[0-9:.]+ \([0-9]+\)\|//' | cut -c1-250 | head -120
done
