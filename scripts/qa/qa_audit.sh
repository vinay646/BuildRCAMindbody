#!/usr/bin/env bash
# READ-ONLY: Setup Audit Trail entries about validation rules / region since 14 Nov.
set -uo pipefail
sf data query --query "SELECT CreatedDate, CreatedBy.Name, Section, Action, Display FROM SetupAuditTrail WHERE CreatedDate >= 2026-11-14T00:00:00Z ORDER BY CreatedDate LIMIT 2000" --target-org target --json > audit.json
jq -r '.message // empty' audit.json
jq -r '.result.records[]? | select((.Section // "" | test("Validation";"i")) or (.Display // "" | test("Region|Pricebook|validation rule";"i"))) | "\(.CreatedDate[0:16]) | \(.CreatedBy.Name) | \(.Section) | \(.Action) | \(.Display)"' audit.json
