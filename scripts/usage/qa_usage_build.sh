#!/usr/bin/env bash
# CHANGES QA: runs the usage build Apex, then refreshes the rate card decision tables
API="/services/data/v$ORG_API"
sf apex run --file scripts/usage/apex/qa_usage_build.apex --target-org target --json 2>&1 | jq -r '.result.logs // .message' | grep 'USER_DEBUG' | grep -o 'QAU .*' | head -2
for dn in $(sf data query --query "SELECT DeveloperName FROM DecisionTable WHERE DeveloperName LIKE '%Rate%'" --target-org target --json | jq -r '.result.records[].DeveloperName'); do
  sf api request rest "$API/actions/standard/refreshDecisionTable" --method POST --body "{\"inputs\":[{\"DecisionTableApiName\":\"$dn\"}]}" --target-org target >/dev/null 2>&1 && R="$R $dn"
done; echo "REFRESHED $(echo $R | wc -w) rate decision tables"
