#!/usr/bin/env bash
# READ-ONLY: flows created or changed by the team since 1 Nov 2026, with their full logic (compact).
set -uo pipefail
API="/services/data/v$ORG_API"
echo "== FLOW LIST"
sf data query --use-tooling-api --query "SELECT Id, DeveloperName, LatestVersion.VersionNumber, ActiveVersion.VersionNumber, LastModifiedDate, LastModifiedBy.Name, CreatedDate, CreatedBy.Name FROM FlowDefinition WHERE LastModifiedDate >= 2026-11-01T00:00:00Z ORDER BY DeveloperName" --target-org target --json | jq -c '[.result.records[] | {name: .DeveloperName, latest: .LatestVersion.VersionNumber, active: .ActiveVersion.VersionNumber, created: .CreatedDate[0:10], by: .CreatedBy.Name, modified: .LastModifiedDate[0:16], modBy: .LastModifiedBy.Name}]'
for name in $(sf data query --use-tooling-api --query "SELECT DeveloperName FROM FlowDefinition WHERE LastModifiedDate >= 2026-11-01T00:00:00Z" --target-org target --json | jq -r '.result.records[].DeveloperName'); do
  id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = '$name' ORDER BY VersionNumber DESC LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty')
  [ -z "$id" ] && continue
  sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target > f.json 2>&1
  echo "== FLOW $name"
  jq -c 'def v: (.stringValue // .numberValue // .booleanValue // .elementReference // .formulaExpression); .Metadata as $m | $m | {label, status, processType, apiVersion,
    start: {object: .start.object, type: .start.triggerType, when: .start.recordTriggerType, filterLogic: .start.filterLogic, filters: [.start.filters[]? | "\(.field) \(.operator) \(.value|v)"], formula: .start.filterFormula, scheduled: (.start.scheduledPaths|length)},
    lookups: [.recordLookups[]? | {name, object, filters: [.filters[]? | "\(.field) \(.operator) \(.value|v)"], first: .getFirstRecordOnly, fault: (.faultConnector.targetReference != null)}],
    decisions: [.decisions[]? | {name, rules: [.rules[]? | {name, logic: .conditionLogic, conds: [.conditions[]? | "\(.leftValueReference) \(.operator) \(.rightValue|v)"]}]}],
    loops: [.loops[]? | {name, collection: .collectionReference}],
    updates: [.recordUpdates[]? | {name, object, ref: .inputReference, filters: [.filters[]? | "\(.field) \(.operator) \(.value|v)"], fields: [.inputAssignments[]? | "\(.field)=\(.value|v)"], fault: (.faultConnector.targetReference != null)}],
    creates: [.recordCreates[]? | {name, object, fault: (.faultConnector.targetReference != null)}],
    assignments: [.assignments[]? | {name, items: [.assignmentItems[]? | "\(.assignToReference) \(.operator) \(.value|v)"]}],
    formulas: [.formulas[]? | {name, expression}],
    errors: [.customErrors[]? | {name, msg: [.customErrorMessages[]? | .errorMessage]}],
    actions: [.actionCalls[]? | {name, actionName, actionType}], subflows: [.subflows[]? | .flowName]}' f.json | head -c 6000; echo
done
