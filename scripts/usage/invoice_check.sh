#!/usr/bin/env bash
# Read-only: dump an invoice and everything behind it. INVOICE_ID env (default the one under review).
set -uo pipefail
INV="${INVOICE_ID:-3tthm000000IlrhAAC}"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes) | with_entries(select(.value != null))] // .message'; }
ids() { jq -r '[.[] | .'"$1"' // empty] | unique | map("'"'"'"+.+"'"'"'") | join(",")'; }
echo "== invoice"; inv=$(q "SELECT FIELDS(ALL) FROM Invoice WHERE Id='$INV' LIMIT 1"); echo "$inv"
echo "== lines"; lines=$(q "SELECT FIELDS(ALL) FROM InvoiceLine WHERE InvoiceId='$INV' LIMIT 200"); echo "$lines"
ref=$(echo "$lines" | ids ReferenceEntityId); bs=$(echo "$lines" | ids BillingScheduleId); prod=$(echo "$lines" | ids Product2Id)
acct=$(echo "$inv" | ids BillToContactId); ba=$(echo "$inv" | ids BillingAccountId); ent=$(echo "$inv" | ids ReferenceEntityId)
echo "== products"; [ -n "$prod" ] && q "SELECT Id, ProductCode, Name, Type, BillingPolicyId, TaxPolicyId FROM Product2 WHERE Id IN ($prod)"
echo "== order items"; [ -n "$ref" ] && oi=$(q "SELECT Id, OrderId, Order.OrderNumber, Order.Status, Order.AccountId, Order.EffectiveDate, Product2.ProductCode, Quantity, UnitPrice, NetUnitPrice, TotalPrice, ServiceDate, EndDate, BillingFrequency2, PeriodBoundary, PeriodBoundaryDay, ProrationPolicyId, QuoteLineItemId FROM OrderItem WHERE Id IN ($ref)") && echo "$oi"
ord=$(echo "${oi:-[]}" | ids OrderId)
echo "== order"; [ -n "$ord" ] && q "SELECT FIELDS(STANDARD) FROM Order WHERE Id IN ($ord)"
echo "== all items on order"; [ -n "$ord" ] && q "SELECT Id, Product2.ProductCode, Quantity, NetUnitPrice, TotalPrice, ServiceDate, EndDate, BillingFrequency2 FROM OrderItem WHERE OrderId IN ($ord)"
echo "== billing schedules (by order item)"; [ -n "$ref" ] && q "SELECT FIELDS(ALL) FROM BillingSchedule WHERE ReferenceEntityItemId IN ($ref) LIMIT 50"
echo "== billing schedules (by line)"; [ -n "$bs" ] && q "SELECT FIELDS(ALL) FROM BillingSchedule WHERE Id IN ($bs) LIMIT 50"
echo "== billing period items"; [ -n "$bs" ] && q "SELECT FIELDS(ALL) FROM BillingPeriodItem WHERE BillingScheduleId IN ($bs) LIMIT 100"
echo "== billing account"; [ -n "$ba" ] && q "SELECT FIELDS(ALL) FROM BillingAccount WHERE Id IN ($ba) LIMIT 5"
oacct=$(echo "${oi:-[]}" | jq -r '[.[].Order.AccountId // empty] | unique | map("'"'"'"+.+"'"'"'") | join(",")')
echo "== order account"; [ -n "$oacct" ] && q "SELECT Id, Name, ParentId, CurrencyIsoCode, BillingCountry, ShippingCountry, ShippingState FROM Account WHERE Id IN ($oacct)"
echo "== account custom fields"; [ -n "$oacct" ] && sf data query --query "SELECT FIELDS(CUSTOM) FROM Account WHERE Id IN ($oacct) LIMIT 5" --target-org target --json | jq -c '[.result.records[]? | del(.attributes) | with_entries(select(.value != null))]'
echo "== tax lines"; q "SELECT FIELDS(ALL) FROM InvoiceLineTax WHERE InvoiceLine.InvoiceId='$INV' LIMIT 50"
echo "== other invoices same order/account"; [ -n "$ba" ] && q "SELECT Id, DocumentNumber, Status, InvoiceDate, TotalAmount, TotalAmountWithTax FROM Invoice WHERE BillingAccountId IN ($ba) ORDER BY CreatedDate"
echo "== payments/applications"; q "SELECT FIELDS(STANDARD) FROM PaymentLineInvoice WHERE InvoiceId='$INV' LIMIT 20"
