#!/usr/bin/env bash
# Read-only: what the deactivated QA quote-line term flows did (trigger, entry, actions, fields set)
t() { sf data query --use-tooling-api --query "$1" --target-org target --json 2>/dev/null; }
for F in Update_Quote_Line_Subscription_Term Update_Quote_Line_Subscription_Term_Based_On_Quote Update_Quote_Line_Subscription_Term_End_Date; do
  ID=$(t "SELECT LatestVersionId FROM FlowDefinition WHERE DeveloperName = '$F'" | jq -r '.result.records[0].LatestVersionId')
  echo "==== $F"
  t "SELECT Metadata FROM Flow WHERE Id = '$ID'" | jq -c '.result.records[0].Metadata | {type: .processType, start: (.start | {object, triggerType, recordTriggerType, filterFormula, filters: [.filters[]? | [.field, .operator, (.value | (.stringValue // .elementReference // .numberValue // .booleanValue) | tostring)]]}), actions: [.actionCalls[]? | [.name, .actionName, .actionType]], sets: ([.assignments[]?.assignmentItems[]? | [.assignToReference, (.value | (.elementReference // .stringValue // .numberValue) | tostring)]] + [.recordUpdates[]? | {upd: .name, obj: .object, ref: .inputReference, fields: [.inputAssignments[]? | [.field, (.value | (.elementReference // .stringValue // .numberValue) | tostring)]]}]), formulas: [.formulas[]? | [.name, .expression]]}' | cut -c1-2500
done
