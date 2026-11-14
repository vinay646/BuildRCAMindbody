#!/usr/bin/env bash
# READ-ONLY QA for MB-CR-03 Add-on eligibility.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
echo "== ALL CONSTRAINT/RULE VERSIONS"; raw "SELECT Id, DeveloperName, Status, VersionNumber FROM ExpressionSetDefinitionVersion WHERE DeveloperName LIKE '%Plan%' OR DeveloperName LIKE '%CR%' OR DeveloperName LIKE '%Concierge%' OR DeveloperName LIKE '%Mindbody%'" "--use-tooling-api"
for o in ProductConfigurationRule ProductConfigRule ProductConfigurationRuleDefinition; do echo "== $o"; raw "SELECT FIELDS(STANDARD) FROM $o LIMIT 50"; done
echo "== SOBJECTS LIKE RULE"; sf api request rest "$API/sobjects" --target-org target | jq -r '[.sobjects[].name | select(test("ConfigurationRule|ConfigRule|ProductRule";"i"))] | join(" ")'
