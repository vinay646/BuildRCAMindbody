#!/usr/bin/env bash
# READ ONLY: invoices created today and their lines
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
echo "invoices today: $(q "SELECT Id, DocumentNumber, Status, CurrencyIsoCode, TotalAmount, TotalTaxAmount, TotalAmountWithTax, BillingAccount.Name, InvoiceDate, DueDate FROM Invoice WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 3" '[.result.records[] | del(.attributes) | .BillingAccount = .BillingAccount.Name]')"
iid=$(q "SELECT Id FROM Invoice WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 1" '.result.records[0].Id' | tr -d '"')
echo "lines: $(q "SELECT Product2.ProductCode, Quantity, UnitPrice, ChargeAmount, TaxAmount, LineAmount, StartDate, EndDate, Type FROM InvoiceLine WHERE InvoiceId = '$iid'" '[.result.records[] | del(.attributes) | .Product2 = .Product2.ProductCode]' 2>&1 | head -c 1500)"
echo "schedules (order 118): $(q "SELECT Status, NextBillingDate, BilledThroughPeriod FROM BillingSchedule WHERE ReferenceEntity.Name = '00000118'" '[.result.records[] | del(.attributes)]' 2>&1 | head -c 400)"
echo "errors: $(q "SELECT Status, ErrorMessage, CreatedDate FROM BillingScheduleGroup WHERE CreatedDate = TODAY LIMIT 3" '[.result.records[] | del(.attributes)]' 2>&1 | head -c 300)"
