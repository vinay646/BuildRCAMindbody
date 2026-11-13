#!/usr/bin/env bash
set -uo pipefail
API="/services/data/v$ORG_API"
echo "TOOLING $(sf api request rest "$API/tooling/sobjects" --target-org target | jq -c '[.sobjects[] | select(.name|test("RuleLib|TagMap|CustomTag|Mapping";"i")) | .name]')"
echo "DATA (all, incl. hidden) $(sf api request rest "$API/sobjects" --target-org target | jq -c '[.sobjects[] | select(.name|test("TagMap|CustomTag|ContextTag|RuleLibraryVersion|RuleLibVer";"i")) | .name]')"
for p in "connect/rule-library" "connect/rule-libraries" "connect/business-rules" "connect/business-rules/rule-library" "connect/global-promotions-management/rule-library"; do echo "GET /$p: $(sf api request rest "$API/$p" --target-org target 2>&1 | tr -d '\n' | head -c 400)"; done
V=$(sf data query --query "SELECT Id FROM RuleLibraryVersion WHERE ApiName = 'RLM_RuleLibrary_V1'" --target-org target --json | jq -r '.result.records[0].Id')
echo "VERSION record: $(sf api request rest "$API/sobjects/RuleLibraryVersion/$V" --target-org target | jq -c 'del(.attributes)')"
