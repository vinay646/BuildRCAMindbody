#!/usr/bin/env bash
# Read-only: shows the T06 order 00000122 invoice, lines and billing schedule status
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
oid=$(q "SELECT Id FROM Order WHERE OrderNumber = '00000122'" '.result.records[0].Id' | tr -d '"')
echo "bs: $(q "SELECT Status, TotalAmount, NextBillingDate FROM BillingSchedule WHERE ReferenceEntityId = '$oid'" '[.result.records[] | del(.attributes)]')"
echo "inv: $(q "SELECT Id, DocumentNumber, Status, CurrencyIsoCode, TotalAmount, TotalTaxAmount, TotalAmountWithTax, InvoiceDate, DueDate FROM Invoice WHERE BillingAccountId IN (SELECT AccountId FROM Order WHERE Id = '$oid') ORDER BY CreatedDate DESC" '[.result.records[] | del(.attributes)]')"
iid=$(q "SELECT Id FROM Invoice WHERE BillingAccountId IN (SELECT AccountId FROM Order WHERE Id = '$oid') ORDER BY CreatedDate DESC LIMIT 1" '.result.records[0].Id' | tr -d '"')
[ "$iid" != "null" ] && echo "lines: $(q "SELECT Product2.ProductCode, Quantity, UnitPrice, ChargeAmount, TaxAmount, StartDate, EndDate FROM InvoiceLine WHERE InvoiceId = '$iid'" '[.result.records[] | del(.attributes) | .Product2 = .Product2.ProductCode]')"
