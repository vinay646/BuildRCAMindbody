#!/usr/bin/env bash
# CHANGES test data: generates an invoice for test order 00000118's billing schedules (standard invoicing API), shows invoice, lines, tax
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
oid=$(q "SELECT Id FROM Order WHERE OrderNumber = '00000118'" '.result.records[0].Id' | tr -d '"')
ids=$(q "SELECT Id FROM BillingSchedule WHERE ReferenceEntityId = '$oid'" '[.result.records[].Id]')
d=$(date -u +%Y-%m-%d)
for path in "/commerce/invoicing/invoices/collection/actions/generate"; do
  echo "== POST $path"
  sf api request rest "$API$path" --method POST --body "{\"billingScheduleIds\":$ids,\"action\":\"Draft\",\"invoiceDate\":\"$d\",\"targetDate\":\"$d\"}" --target-org target 2>&1 | head -c 800; echo
done
sleep 30
inv=$(q "SELECT Id, DocumentNumber, Status, CurrencyIsoCode, TotalAmount, TotalTaxAmount, TotalAmountWithTax, BillingAccountId, InvoiceDate, DueDate FROM Invoice WHERE ReferenceEntityId = '$oid' ORDER BY CreatedDate DESC LIMIT 1" '.result.records[0]')
echo "invoice: $(echo $inv | jq -c 'del(.attributes)')"
iid=$(echo $inv | jq -r .Id)
[ "$iid" != "null" ] && echo "lines: $(q "SELECT Product2.ProductCode, Quantity, UnitPrice, ChargeAmount, TaxAmount, StartDate, EndDate, Type FROM InvoiceLine WHERE InvoiceId = '$iid'" '[.result.records[] | del(.attributes) | .Product2 = .Product2.ProductCode]' 2>&1 | head -c 1200)"
