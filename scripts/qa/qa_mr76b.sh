#!/usr/bin/env bash
# READ-ONLY: category qualification rows (hardware by region) and the active qualification procedure's steps.
set -uo pipefail
API="/services/data/v$ORG_API"
sf data query --query "SELECT FIELDS(ALL) FROM ProductCategoryQualification LIMIT 50" --target-org target --json | jq -c '[.result.records[]? | with_entries(select(.value != null and (.key|test("attributes|Created|LastModified|System|IsDeleted|LastViewed|LastReferenced|Currency")|not)))]'
sf data query --query "SELECT FIELDS(ALL) FROM ProductCategoryDisqual LIMIT 50" --target-org target --json | jq -c '[.result.records[]? | with_entries(select(.value != null and (.key|test("attributes|Created|LastModified|System|IsDeleted|LastViewed|LastReferenced|Currency")|not)))]'
sf data query --query "SELECT Id, Name FROM ProductCategory WHERE Name = 'Hardware'" --target-org target --json | jq -c '[.result.records[] | {Id, Name}]'
id=$(sf data query --use-tooling-api --query "SELECT Id FROM ExpressionSetDefinitionVersion WHERE Status = 'Active' AND DeveloperName LIKE 'RLM_ProductDiscoveryQualification%'" --target-org target --json | jq -r '.result.records[0].Id')
sf api request rest "$API/tooling/sobjects/ExpressionSetDefinitionVersion/$id" --target-org target | jq -c '[.Metadata | .. | objects | select(has("name") and (has("actionType") or has("stepType"))) | {name, stepType, actionType, dt: ([.customElement?.parameters[]? | select(.name|test("DecisionTable|decisionTable|tableName";"i")) | .value] | join(","))}]'
