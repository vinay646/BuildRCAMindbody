#!/usr/bin/env bash
# READ-ONLY: EU qualification rows and status of the hardware constraint model.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes) | with_entries(select(.value != null and (.key|test("^(IsDeleted|SystemModstamp|LastViewedDate|LastReferencedDate|LastModifiedById|CreatedById|OwnerId|CreatedDate|LastModifiedDate)$")|not)))] else {error: .message} end'; }
echo "== CATEGORY QUALIFICATION ROWS"; raw "SELECT FIELDS(ALL) FROM ProductCategoryQualification LIMIT 50"
echo "== CATEGORY DISQUALIFICATION ROWS"; raw "SELECT FIELDS(ALL) FROM ProductCategoryDisqual LIMIT 50"
echo "== CONSTRAINT MODEL VERSIONS"; raw "SELECT Id, DeveloperName, Status, VersionNumber, StartDate, EndDate FROM ExpressionSetDefinitionVersion WHERE Id IN ('9QBi8000000181xGAA','9QBi800000016plGAA','9QBi8000000180LGAQ','9QBi80000000w5kGAA','9QBi800000016ubGAA')" "--use-tooling-api"
echo "== HARDWARE CML FULL"; sf api request rest "$API/tooling/sobjects/ExpressionSetDefinitionVersion/9QBi8000000181xGAA/ConstraintModel" --target-org target | head -c 1200; echo
echo "== QUALIFICATION PROCEDURE STEPS"; sf api request rest "$API/tooling/sobjects/ExpressionSetDefinitionVersion/9QBi80000000w5kGAA" --target-org target | jq -c '.Metadata | [.. | objects | select(has("name") and (has("decisionTableApiName") or has("actionType") or has("elementType"))) | {name, type: (.actionType // .elementType), table: .decisionTableApiName}]' 2>/dev/null | head -c 2500; echo
echo "== EU ACCOUNT FIELD"; sf api request rest "$API/sobjects/Account/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Region|Country|Entity";"i")) | {name, type, picklist: [.picklistValues[]?.value]}]'
