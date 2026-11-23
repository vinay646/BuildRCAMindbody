#!/usr/bin/env bash
# Read-only: validation rules and flows on Quote / QuoteLineItem changed since 19 Nov (term months check for MR-72 test 3)
t() { sf data query --use-tooling-api --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
echo "VR $(t "SELECT ValidationName, Active, EntityDefinition.QualifiedApiName, LastModifiedDate, ErrorMessage FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Quote','QuoteLineItem') AND LastModifiedDate >= 2026-11-19T00:00:00Z")"
echo "FLOWS $(sf data query --query "SELECT ApiName, IsActive, LastModifiedDate FROM FlowDefinitionView WHERE LastModifiedDate >= 2026-11-19T00:00:00Z" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]')"
for id in $(t "SELECT Id FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Quote','QuoteLineItem') AND LastModifiedDate >= 2026-11-19T00:00:00Z" | jq -r '.[].Id'); do
  echo "FORMULA $id $(t "SELECT Metadata FROM ValidationRule WHERE Id = '$id'" | jq -c '.[0].Metadata.errorConditionFormula' | cut -c1-600)"
done
