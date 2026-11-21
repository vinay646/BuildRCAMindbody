#!/usr/bin/env bash
# CHANGES the org if valid: creates the daily invoice scheduler "MB Daily Invoice Run" (Posted invoices) via the Connect API
API="/services/data/v$ORG_API"
d=$(date -u -d '+1 day' +%Y-%m-%d)
B=${BODY:-"{\"schedulerName\":\"MB Daily Invoice Run\",\"invoiceStatus\":\"Posted\",\"status\":\"Active\",\"startDate\":\"$d\",\"frequencyCadence\":\"Daily\",\"preferredTime\":\"06:00\"}"}
echo "body: $B"
sf api request rest "$API/commerce/invoicing/invoice-schedulers" --method POST --body "$B" --target-org target 2>&1 | head -c 800; echo
