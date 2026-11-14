#!/usr/bin/env bash
# READ-ONLY: logic of the active Quote Line Item flows (conditions, products checked, error messages).
set -uo pipefail
API="/services/data/v$ORG_API"
for f in Validate_Single_Bundle_Per_Quote Validate_Hardware_Ship_To_Address Quote_Term_and_Account_s_Master_Contract_Validation; do
  id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = '$f' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty')
  echo "== FLOW $f ($id)"
  [ -z "$id" ] && continue
  sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target > flow.json 2>&1
  jq -c '.Metadata | {start: .start | {object, recordTriggerType, triggerType, filters, filterFormula}, recordLookups: [.recordLookups[]? | {name, object, filters: [.filters[]? | {field, operator, value}]}], decisions: [.decisions[]? | {name, rules: [.rules[]? | {name, conditions: [.conditions[]? | {left: .leftValueReference, op: .operator, right: .rightValue}]}]}], formulas: [.formulas[]? | {name, expression}], errors: [.. | objects | select(has("errorMessage")) | .errorMessage] , customErrors: [.customErrors[]? | {name, messages: [.customErrorMessages[]? | .errorMessage]}], assignments: [.assignments[]? | .name]}' flow.json | head -c 5000; echo
done
