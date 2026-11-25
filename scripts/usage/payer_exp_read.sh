#!/usr/bin/env bash
# Read-only: results of the payer experiment for the latest "MBPayer Location" account
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
CH=$(q "SELECT Id FROM Account WHERE Name LIKE 'MBPayer Location%' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id')
echo "ORDERS $(q "SELECT Id, OrderNumber, Status, Account.Name, BillToContact.Name, BillToContact.Account.Name FROM Order WHERE AccountId = '$CH'" | jq -c '[.[] | {n: .OrderNumber, s: .Status, acct: .Account.Name, billTo: .BillToContact.Name, billToAcct: .BillToContact.Account.Name}]')"
OID=$(q "SELECT Id FROM Order WHERE AccountId = '$CH' LIMIT 1" | jq -r '.[0].Id')
echo "BILLING SCHEDULES $(q "SELECT BillingAccount.Name, Status, BillToContact.Name FROM BillingSchedule WHERE ReferenceEntityId = '$OID'" 2>&1 | jq -c '[.[] | [.BillingAccount.Name, .Status, .BillToContact.Name]]' 2>/dev/null)"
echo "BS FIELDS $(sf data query --query "SELECT FIELDS(ALL) FROM BillingSchedule WHERE ReferenceEntityId = '$OID' LIMIT 1" --target-org target --json | jq -c '.result.records[0] | with_entries(select((.key|test("Account|Contact|Grouping";"i")) and .value != null))')"
echo "ASSETS $(q "SELECT Name, Account.Name FROM Asset WHERE AccountId = '$CH'" | jq -c '[.[] | [.Name, .Account.Name]]')"
