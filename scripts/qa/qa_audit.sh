#!/usr/bin/env bash
# READ-ONLY: Setup Audit Trail entries for validation rules and flows since 14 Nov.
set -uo pipefail
sf data query --query "SELECT CreatedDate, CreatedBy.Name, Section, Action, Display FROM SetupAuditTrail WHERE CreatedDate >= 2026-11-14T00:00:00Z AND (Section = 'Validation Rules' OR Display LIKE '%Region%' OR Display LIKE '%Pricebook%' OR Display LIKE '%validation%') ORDER BY CreatedDate" --target-org target --json | jq -r '.result.records[] | "\(.CreatedDate[0:16]) | \(.CreatedBy.Name) | \(.Action) | \(.Display)"'
