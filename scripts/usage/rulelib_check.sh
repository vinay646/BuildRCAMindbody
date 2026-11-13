#!/usr/bin/env bash
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
echo "LIBRARY $(q "SELECT Id, Name, ApiName, UsageType, Status, ContextDefinitionName, RuleLibraryDefinitionId FROM RuleLibrary WHERE ApiName = 'RLM_RuleLibrary'")"
echo "VERSIONS $(q "SELECT Id, Name, ApiName, Status, VersionNumber, StartDateTime, ContextDefinitionName, RuleLibraryDefVersionId FROM RuleLibraryVersion WHERE RuleLibrary.ApiName = 'RLM_RuleLibrary'")"
