#!/usr/bin/env bash
# READ-ONLY: setup audit trail since 19 Nov 09:00 UTC (no user management rows), and current state of Region fields.
set -uo pipefail
API="/services/data/v$ORG_API"
sf data query --query "SELECT CreatedDate, CreatedBy.Name, Section, Display FROM SetupAuditTrail WHERE CreatedDate >= 2026-11-19T09:00:00Z AND Section != 'Manage Users' ORDER BY CreatedDate LIMIT 800" --target-org target --json | jq -r '.result.records[]? | "\(.CreatedDate[:16]) | \(.CreatedBy.Name) | \(.Section) | \(.Display)"' | grep -v "Lightning Page" | cut -c1-260
echo "== Lightning page changes since 19 Nov 09:00: $(sf data query --query "SELECT COUNT() FROM SetupAuditTrail WHERE CreatedDate >= 2026-11-19T09:00:00Z AND Section = 'Lightning Pages'" --target-org target --json | jq '.result.totalSize')"
echo "== Region fields now"
for o in Account Opportunity Quote ProductQualification; do echo "   $o $(sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.name|test("region";"i")) | {n: .name, t: .type, f: (.calculatedFormula // "" | .[0:80])}]')"; done
echo "== Validation rules now (Opportunity / Quote / QuoteLineItem)"
sf data query --use-tooling-api --query "SELECT EntityDefinition.QualifiedApiName, ValidationName, Active, LastModifiedDate FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Opportunity','Quote','QuoteLineItem','Account')" --target-org target --json | jq -r '.result.records[] | "   \(.EntityDefinition.QualifiedApiName).\(.ValidationName) active=\(.Active) mod=\(.LastModifiedDate[:16])"'
