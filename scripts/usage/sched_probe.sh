#!/usr/bin/env bash
# CHANGES the org if valid: creates the daily invoice scheduler "MB Daily Invoice Run" via the Connect API (tries criteria variants)
API="/services/data/v$ORG_API"
d=$(date -u -d '+1 day' +%Y-%m-%d)
base="\"schedulerName\":\"MB Daily Invoice Run\",\"invoiceStatus\":\"Posted\",\"status\":\"Active\",\"startDate\":\"$d\",\"frequencyCadence\":\"Daily\",\"preferredTime\":\"06:00\",\"invoiceDateOffset\":0,\"targetDateOffset\":0"
for c in "BillingSchedule:CurrencyIsoCode:USD" "BillingSchedule:LegalEntityId:x" "Account:CurrencyIsoCode:USD" "BillingScheduleGroup:CurrencyIsoCode:USD" "Account:Name:x"; do
  IFS=: read o f v <<<"$c"
  B="{$base,\"filterCriteria\":[{\"objectName\":\"$o\",\"criteriaSequence\":1,\"operation\":\"Equals\",\"value\":\"$v\",\"fieldName\":\"$f\"}]}"
  r=$(sf api request rest "$API/commerce/invoicing/invoice-schedulers" --method POST --body "$B" --target-org target 2>&1 | tr -d '\n' | head -c 300)
  echo "$c => $r"
  echo "$r" | grep -q '"id"\|schedulerId' && break
done
