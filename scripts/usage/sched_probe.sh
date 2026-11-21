#!/usr/bin/env bash
# CHANGES the org if valid: creates the daily invoice scheduler "MB Daily Invoice Run" via the Connect API (tries body variants)
API="/services/data/v$ORG_API"
d=$(date -u -d '+1 day' +%Y-%m-%d)
base="\"schedulerName\":\"MB Daily Invoice Run\",\"invoiceStatus\":\"Posted\",\"startDate\":\"$d\",\"frequencyCadence\":\"Daily\",\"preferredTime\":\"06:00\",\"invoiceDateOffset\":0,\"targetDateOffset\":0"
for B in "{$base,\"status\":\"Draft\"}" "{$base,\"status\":\"Active\",\"filterCriteria\":[{\"objectName\":\"BillingSchedule\",\"criteriaSequence\":1,\"operation\":\"Equals\",\"value\":\"ReadyForInvoicing\",\"fieldName\":\"Status\"}]}"; do
  echo "body: ${B:0:200}"
  r=$(sf api request rest "$API/commerce/invoicing/invoice-schedulers" --method POST --body "$B" --target-org target 2>&1 | head -c 600); echo "$r"
  echo "$r" | grep -q '"id"\|"success": *true\|schedulerId' && break
done
