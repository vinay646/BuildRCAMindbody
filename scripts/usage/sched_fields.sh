#!/usr/bin/env bash
# READ ONLY: invoice scheduler objects and fields
for o in BillingBatchScheduler BillingBatchFilterCriteria InvoiceBatchRun; do
  echo "== $o: $(sf sobject describe --sobject $o --target-org target --json 2>/dev/null | jq -c '[.result.fields[]? | select(.createable) | "\(.name):\(.type)\(if .picklistValues|length>0 then "=" + ([.picklistValues[].value]|join("/")) else "" end)"]' | cut -c1-1500)"
done
