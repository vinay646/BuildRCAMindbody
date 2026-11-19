#!/usr/bin/env bash
# READ ONLY: summarise the debug logs captured since the trace was switched on (DML on quote lines / adjustments, flows, errors).
set -uo pipefail
ids=$(sf data query --use-tooling-api --query "SELECT Id, Operation, Request, StartTime, LogLength, Status FROM ApexLog WHERE StartTime = TODAY ORDER BY StartTime" --target-org target --json | jq -r '.result.records[] | "\(.Id)|\(.StartTime)|\(.Operation)|\(.Request)|\(.Status)"')
echo "$ids" | while IFS='|' read -r id t op req st; do
  [ -z "$id" ] && continue
  body=$(sf api request rest "/services/data/v$ORG_API/tooling/sobjects/ApexLog/$id/Body" --target-org target 2>/dev/null)
  echo "== $t $op $req $st"
  echo "$body" | grep -E "DML_BEGIN.*(QuoteLineItem|QuoteLinePriceAdjustment|Quote)|FLOW_START_INTERVIEW_BEGIN|FLOW_ELEMENT_ERROR|FATAL_ERROR|EXCEPTION_THROWN|CODE_UNIT_STARTED.*(RepriceQuotesPST|Flow)|Op:Delete" | sed -E 's/^[0-9:.]+ \([0-9]+\)\|//' | head -40
done
