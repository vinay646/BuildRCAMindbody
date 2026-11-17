#!/usr/bin/env bash
# Regression probe only: Apex inserts that are ROLLED BACK (nothing saved). Prints raw errors.
set -uo pipefail
D=$(dirname "$0")
sf apex run --file "$D/apex/regression_rollback.apex" --target-org target --json > apex.json 2>&1 || true
jq -c '{status, message, name, compiled: .result.compiled, success: .result.success, line: .result.line, problem: .result.compileProblem, exception: .result.exceptionMessage}' apex.json 2>/dev/null || head -c 3000 apex.json
jq -r '.result.logs // ""' apex.json 2>/dev/null | grep -o 'RESULT.*' || true
API="/services/data/v$ORG_API"
echo "== REGION RULES NOW"
for id in $(sf data query --use-tooling-api --query "SELECT Id FROM ValidationRule WHERE ValidationName LIKE '%Region%'" --target-org target --json | jq -r '.result.records[].Id'); do
  sf api request rest "$API/tooling/sobjects/ValidationRule/$id" --target-org target | jq -c '{obj: .EntityDefinitionId, name: .ValidationName, active: .Metadata.active, modified: .LastModifiedDate, formula: (.Metadata.errorConditionFormula|gsub("\\s+";" ")), msg: .Metadata.errorMessage}'
done
echo "== PRICE BOOK FLOW NOW"
sf data query --use-tooling-api --query "SELECT DeveloperName, ActiveVersion.VersionNumber, LatestVersion.VersionNumber, LastModifiedDate FROM FlowDefinition WHERE LastModifiedDate >= 2026-11-17T00:00:00Z" --target-org target --json | jq -c '[.result.records[] | {n: .DeveloperName, active: .ActiveVersion.VersionNumber, latest: .LatestVersion.VersionNumber, at: .LastModifiedDate}]'
id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = 'Opportunity_Update_PriceBook_Currency_Based_on_Account_Field' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty')
sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target | jq -c 'def v: (.stringValue // .numberValue // .elementReference); .Metadata | {type: .start.triggerType, when: .start.recordTriggerType, filters: [.start.filters[]? | "\(.field) \(.operator) \(.value|v)"], updates: [.recordUpdates[]? | {fields: [.inputAssignments[]? | "\(.field)=\(.value|v)"]}], assignments: [.assignments[]? | [.assignmentItems[]? | "\(.assignToReference)=\(.value|v)"]]}'
