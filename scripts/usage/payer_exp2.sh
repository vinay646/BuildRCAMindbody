#!/usr/bin/env bash
# CHANGES test data in dev: generates the invoice for the latest MBPayer order, then re-points the Draft invoice's billing account to the payer; reports results
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
CH=$(q "SELECT Id, Resolved_Payer__c FROM Account WHERE Name LIKE 'MBPayer Location%' ORDER BY CreatedDate DESC LIMIT 1"); CID=$(echo "$CH" | jq -r '.[0].Id'); PAY=$(echo "$CH" | jq -r '.[0].Resolved_Payer__c')
OID=$(q "SELECT Id FROM Order WHERE AccountId = '$CID' LIMIT 1" | jq -r '.[0].Id')
BS=$(q "SELECT Id FROM BillingSchedule WHERE ReferenceEntityId = '$OID'" | jq -c '[.[].Id]'); d=$(date -u +%Y-%m-%d)
echo "generate: $(sf api request rest "$API/commerce/invoicing/invoices/collection/actions/generate" --method POST --body "{\"billingScheduleIds\":$BS,\"action\":\"Draft\",\"invoiceDate\":\"$d\",\"targetDate\":\"$d\"}" --target-org target 2>&1 | jq -c '{success}')"
for _ in 1 2 3 4 5 6; do sleep 15; INV=$(q "SELECT Id, DocumentNumber, Status, BillingAccount.Name, TotalAmount FROM Invoice WHERE BillingAccountId = '$CID' ORDER BY CreatedDate DESC LIMIT 1"); [ "$(echo "$INV" | jq length)" != "0" ] && break; done
echo "INVOICE BEFORE $INV"
IID=$(echo "$INV" | jq -r '.[0].Id // empty')
[ -n "$IID" ] && echo "UPDATE to payer: $(sf data update record --sobject Invoice --record-id $IID --values "BillingAccountId=$PAY" --target-org target --json 2>&1 | jq -c '{status, message}')"
[ -n "$IID" ] && echo "INVOICE AFTER $(q "SELECT DocumentNumber, Status, BillingAccount.Name, BillToContact.Name FROM Invoice WHERE Id = '$IID'")"
[ -n "$IID" ] && echo "POST: $(sf data update record --sobject Invoice --record-id $IID --values "Status=Posted" --target-org target --json 2>&1 | jq -c '{status, message}') -> $(q "SELECT Status, BillingAccount.Name, Balance FROM Invoice WHERE Id = '$IID'")"
