#!/usr/bin/env bash
# READ-ONLY QA for MB-CR-14 Payer override needs a reason.
set -uo pipefail
API="/services/data/v$ORG_API"
id=$(sf data query --use-tooling-api --query "SELECT Id FROM ValidationRule WHERE ValidationName = 'Require_Override_Payer_Reason'" --target-org target --json | jq -r '.result.records[0].Id')
echo "== RULE"; sf api request rest "$API/tooling/sobjects/ValidationRule/$id" --target-org target | jq -c '.Metadata | {active, errorConditionFormula, errorMessage, errorDisplayField}'
echo "== QUOTE FIELDS"; sf api request rest "$API/sobjects/Quote/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Payer|Override";"i")) | {name, label, type, referenceTo, length}]'
