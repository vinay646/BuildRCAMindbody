#!/usr/bin/env bash
# READ-ONLY QA for MB-CR-01 One plan per quote, no duplicate products.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
echo "== MODEL VERSIONS"; raw "SELECT Id, DeveloperName, Status, VersionNumber FROM ExpressionSetDefinitionVersion WHERE DeveloperName LIKE '%Tier%' OR DeveloperName LIKE '%Mindbody%' OR DeveloperName LIKE 'MB%'" "--use-tooling-api"
echo "== CML"; sf api request rest "$API/tooling/sobjects/ExpressionSetDefinitionVersion/9QBi800000016plGAA/ConstraintModel" --target-org target > cml.txt 2>&1; grep -n -v "^\s*//" cml.txt | grep -n -i -E "constraint|message|\"|relation .*\[|enterprise|payment|MB_PAY|type .*: LineItem" | head -60
echo "== FLOWS"; raw "SELECT ApiName, Label, ProcessType, TriggerType, IsActive FROM FlowDefinitionView WHERE ApiName LIKE '%Plan%' OR ApiName LIKE '%Duplicate%' OR ApiName LIKE 'MB_Quote%'"
echo "== FLOWS ON QUOTE LINE"; raw "SELECT ApiName, Label, TriggerType, IsActive FROM FlowDefinitionView WHERE TriggerObjectOrEventLabel = 'Quote Line Item'"
