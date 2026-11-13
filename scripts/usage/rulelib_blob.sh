#!/usr/bin/env bash
set -uo pipefail
API="/services/data/v$ORG_API"
for id in $(sf data query --query "SELECT Id FROM RuleLibraryDefinition" --target-org target --json | jq -r '.result.records[].Id'); do
  echo "===== $id $(sf data query --query "SELECT DeveloperName FROM RuleLibraryDefinition WHERE Id = '$id'" --target-org target --json | jq -r '.result.records[0].DeveloperName')"
  sf api request rest "$API/sobjects/RuleLibraryDefinition/$id/RuleLibrary" --target-org target 2>&1 | head -c 5000; echo
done
