#!/usr/bin/env bash
# Read-only: dumps the logic of the QA location-count flows (start, lookups, decisions, assignments, updates) and Location Count fields
t() { sf data query --use-tooling-api --query "$1" --target-org target --json 2>/dev/null; }
for F in Update_Opportunity_Location_Count Account_Hierarchy_Populate_Root_Account; do
  ID=$(t "SELECT ActiveVersionId FROM FlowDefinition WHERE DeveloperName = '$F'" | jq -r '.result.records[0].ActiveVersionId')
  echo "==== $F ($ID)"
  t "SELECT Metadata FROM Flow WHERE Id = '$ID'" | jq -c '.result.records[0].Metadata | {
    start: (.start | {object, triggerType, recordTriggerType, filterLogic, filters: [.filters[]? | [.field, .operator, (.value | tostring)]], filterFormula, scheduledPaths: [.scheduledPaths[]? | .pathType]}),
    lookups: [.recordLookups[]? | {name, object, filters: [.filters[]? | [.field, .operator, (.value | tostring)]], first: .getFirstRecordOnly}],
    decisions: [.decisions[]? | {name, rules: [.rules[]? | {name, conditions: [.conditions[]? | [.leftValueReference, .operator, (.rightValue | tostring)]]}]}],
    assignments: [.assignments[]? | {name, items: [.assignmentItems[]? | [.assignToReference, .operator, (.value | tostring)]]}],
    loops: [.loops[]? | {name, collectionReference}],
    updates: [.recordUpdates[]? | {name, object, inputReference, filters: [.filters[]? | [.field, .operator, (.value | tostring)]], fields: [.inputAssignments[]? | [.field, (.value | tostring)]]}],
    formulas: [.formulas[]? | {name, expression}],
    faults: [.. | objects | select(has("faultConnector")) | .name]}' | sed 's/{"elementReference":/{"ref":/g' | cut -c1-6000
done
echo "FIELDS Opportunity: $(sf sobject describe --sobject Opportunity --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.name|test("ocation";"i")) | [.name, .type, (.calculatedFormula // "")]]')"
echo "FIELDS Quote: $(sf sobject describe --sobject Quote --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.name|test("ocation";"i")) | [.name, .type, (.calculatedFormula // "")]]')"
