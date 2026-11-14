#!/usr/bin/env bash
# READ-ONLY QA for MB-CR-07: full logic of the hardware flow, compact.
set -uo pipefail
API="/services/data/v$ORG_API"
id=$(sf data query --use-tooling-api --query "SELECT Id, VersionNumber FROM Flow WHERE Definition.DeveloperName = 'Validate_Hardware_Ship_To_Address' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty')
echo "== FLOW $id"
sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target > flow.json 2>&1
jq -c 'def v: (.stringValue // .numberValue // .booleanValue // .elementReference); .Metadata | {label, start: {trigger: .start.recordTriggerType, connector: .start.connector.targetReference},
  lookups: [.recordLookups[]? | {name, filters: [.filters[]? | "\(.field) \(.operator) \(.value|v)"], next: .connector.targetReference}],
  decisions: [.decisions[]? | {name, default: .defaultConnector.targetReference, rules: [.rules[]? | {name, logic: .conditionLogic, next: .connector.targetReference, conds: [.conditions[]? | "\(.leftValueReference) \(.operator) \(.rightValue|v)"]}]}],
  errors: [.customErrors[]? | {name, msg: [.customErrorMessages[]? | .errorMessage]}], creates: [.recordCreates[]? | .name], assignments: [.assignments[]? | .name]}' flow.json
echo "== OTHER VERSIONS"; sf data query --use-tooling-api --query "SELECT VersionNumber, Status, MasterLabel FROM Flow WHERE Definition.DeveloperName = 'Validate_Hardware_Ship_To_Address'" --target-org target --json | jq -c '[.result.records[] | {VersionNumber, Status, MasterLabel}]'
