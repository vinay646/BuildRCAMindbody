#!/usr/bin/env bash
# READ-ONLY: legal entity fields per object, legal entities, and where the billing setup reads them.
set -uo pipefail
API="/services/data/v$ORG_API"
for o in Account Opportunity Quote QuoteLineItem Order OrderItem Contract Asset BillingSchedule Invoice InvoiceLine BillingAccount; do
  echo "$o $(sf api request rest "$API/sobjects/$o/describe" --target-org target 2>/dev/null | jq -c '[.fields[]? | select(.name|test("LegalEntity";"i")) | {n: .name, t: .type, custom, upd: .updateable}]')"
done
echo "== LEGAL ENTITIES"; sf data query --query "SELECT Id, Name, Status, CompanyName, LegalEntityCountry FROM LegalEntity" --target-org target --json | jq -c '[.result.records[] | del(.attributes)]'
echo "== CONTEXT LEGAL ENTITY MAPPINGS"; sf data query --query "SELECT Id, Name FROM ContextDefinition" --target-org target --json | jq -c '[.result.records[]? | .Name]' | head -c 600; echo
