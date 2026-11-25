#!/usr/bin/env bash
# Read-only: account-reference fields on Order, OrderItem, BillingSchedule, Invoice, QuoteLineItem (which field billing reads); a recent billing schedule's account fields vs its order
for o in Quote QuoteLineItem Order OrderItem BillingSchedule BillingScheduleGroup Invoice; do
  echo "$o: $(sf sobject describe --sobject $o --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.type=="reference" and (.referenceTo|index("Account"))) | [.name, .updateable, .createable]]')"
done
OID=$(sf data query --query "SELECT Id FROM Order WHERE OrderNumber = '00000122'" --target-org target --json | jq -r '.result.records[0].Id')
echo "ORDER $(sf data query --query "SELECT AccountId, BillToContactId FROM Order WHERE Id = '$OID'" --target-org target --json | jq -c '.result.records[0] | del(.attributes)')"
echo "ORDERITEM $(sf data query --query "SELECT FIELDS(ALL) FROM OrderItem WHERE OrderId = '$OID' LIMIT 1" --target-org target --json | jq -c '.result.records[0] | with_entries(select((.key|test("Account|Billing|Payer";"i")) and .value != null))')"
echo "BS $(sf data query --query "SELECT FIELDS(ALL) FROM BillingSchedule WHERE ReferenceEntityId = '$OID' LIMIT 1" --target-org target --json | jq -c '.result.records[0] | with_entries(select((.key|test("Account|Contact|Address|Group";"i")) and .value != null))')"
