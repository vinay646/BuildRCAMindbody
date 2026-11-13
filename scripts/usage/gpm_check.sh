#!/usr/bin/env bash
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
tq() { sf data query --use-tooling-api --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
echo "== metadata types (rule/promo/library)"
sf org list metadata-types --target-org target --api-version "$ORG_API" --json 2>/dev/null | jq -r '.result.metadataObjects[]?.xmlName' | grep -iE 'rule|promo|librar|decision' | tr '\n' ' '; echo
echo "== sobjects (rule library / business rules)"
sf api request rest "$API/sobjects" --target-org target | jq -c '[.sobjects[] | select(.name|test("RuleLibrary|BusinessRule|RuleEngine|DecisionMatrix|ExpressionSetDefinition|PromotionRule|Bre";"i")) | .name]'
for o in RuleLibrary RuleLibraryVersion BusinessRulesEngineRuleLibrary; do echo "$o: $(q "SELECT FIELDS(STANDARD) FROM $o LIMIT 10" | head -c 1200)"; done
echo "== expression set definitions incl templates (tooling)"
tq "SELECT DeveloperName, MasterLabel, ProcessType, Template FROM ExpressionSetDefinition" | head -c 3000; echo
echo "== metadata list: ExpressionSetDefinition"
sf org list metadata --metadata-type ExpressionSetDefinition --target-org target --json 2>/dev/null | jq -c '[.result[]?.fullName]'
for t in RuleLibraryDefinition BusinessProcessTypeDefinition DecisionTable; do echo "== list $t: $(sf org list metadata --metadata-type $t --target-org target --json 2>/dev/null | jq -c '[.result[]?.fullName]' | head -c 1500)"; done
echo "== promotion-related permission sets"
q "SELECT Name, Label FROM PermissionSet WHERE Name LIKE '%romo%' OR Label LIKE '%romo%' OR Name LIKE '%GPM%'"
q "SELECT PermissionSetLicense.MasterLabel FROM PermissionSetLicenseAssign WHERE PermissionSetLicense.MasterLabel LIKE '%romo%'"
echo "== settings (any promotion settings)"
rm -rf rs; mkdir rs
sf project retrieve start --api-version "$ORG_API" --metadata "Settings:Promotions" --metadata "Settings:PromotionSettings" --metadata "Settings:Commerce" --metadata "Settings:Loyalty" --target-org target --target-metadata-dir rs --unzip --wait 10 --json > rs.json 2>&1 || true
for f in $(find rs -type f -name '*.settings*'); do echo "-- $f"; sed -e 's/^[[:space:]]*//' "$f" | tr -d '\n' | head -c 1500; echo; done
jq -r '.result.messages // [] | .[] | "WARN \(.problem)"' rs.json 2>/dev/null | head -5
