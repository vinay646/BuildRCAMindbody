#!/usr/bin/env bash
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
V=$(q "SELECT Id FROM RuleLibraryVersion WHERE RuleLibrary.ApiName = 'RLM_RuleLibrary' AND VersionNumber = 1" | jq -r '.[0].Id')
echo "activate: $(sf data update record --sobject RuleLibraryVersion --record-id "$V" --values "Status=Active" --target-org target --json | jq -c '{status, message}')"
echo "VERSION $(q "SELECT ApiName, Status FROM RuleLibraryVersion WHERE Id = '$V'")"
echo "PROCEDURE VERSIONS $(q "SELECT ApiName, Name, VersionNumber, IsActive FROM ExpressionSetVersion WHERE ExpressionSet.ApiName = 'RLM_DefaultPricingProcedure' ORDER BY VersionNumber")"
