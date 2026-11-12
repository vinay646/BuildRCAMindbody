#!/usr/bin/env bash
set -uo pipefail
sf data query --query "SELECT Id, ApiName, Name, VersionNumber, IsActive, StartDateTime, Rank FROM ExpressionSetVersion WHERE ExpressionSet.ApiName = 'RLM_DefaultPricingProcedure' ORDER BY VersionNumber" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'
sf data query --use-tooling-api --query "SELECT Id, DeveloperName, MasterLabel, VersionNumber, Status FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName = 'RLM_DefaultPricingProcedure'" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'
