#!/usr/bin/env bash
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
for o in BillingPolicy BillingTreatment BillingTreatmentItem; do
  echo "== $o fields: $(sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.createable) | {n: .name, t: .type, req: (.nillable|not), pl: ([.picklistValues[]?.value] | if length>0 then . else null end)}]' | head -c 3000)"
done
echo "== policies $(q "SELECT Id, Name, Status, DefaultBillingTreatmentId, BillingTreatmentSelection FROM BillingPolicy")"
echo "== treatments $(q "SELECT Id, Name, Status, BillingPolicyId, IsMilestoneBilling, ExcludeFromBilling FROM BillingTreatment")"
echo "== items $(q "SELECT FIELDS(STANDARD) FROM BillingTreatmentItem LIMIT 10")"
echo "== product2 billing fields $(sf api request rest "$API/sobjects/Product2/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Billing|Tax|Treatment";"i")) | .name]')"
echo "== products with policy $(q "SELECT ProductCode, Name, BillingPolicyId, BillingPolicy.Name, TaxPolicyId FROM Product2 WHERE BillingPolicyId != null LIMIT 15")"
echo "== mindbody products $(q "SELECT ProductCode, BillingPolicyId, TaxPolicyId FROM Product2 WHERE ProductCode LIKE 'MB-%' LIMIT 40")"
echo "== QLI billing fields $(sf api request rest "$API/sobjects/QuoteLineItem/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Billing|Treatment";"i")) | .name]')"
echo "== QB quote lines $(q "SELECT Product2.ProductCode, BillingFrequency, BillingTreatmentId FROM QuoteLineItem WHERE BillingFrequency != 'Monthly' AND BillingFrequency != null LIMIT 5")"
