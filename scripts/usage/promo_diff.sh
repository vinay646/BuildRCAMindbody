#!/usr/bin/env bash
# READ ONLY: compare a working promotion (NewPromo) with the new ones
API="/services/data/v$ORG_API"
for n in NewPromo SWITCH50 LAUNCH3; do
  id=$(sf data query --query "SELECT Id FROM Promotion WHERE Name='$n' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id')
  echo "== $n $id"; sf api request rest "$API/global-promotions-management/promotions/$id" --target-org target 2>&1 | jq -c '.' | cut -c1-2500
  sf data query --query "SELECT FIELDS(STANDARD) FROM Promotion WHERE Id='$id'" --target-org target --json | jq -c '.result.records[0] | del(.attributes)'
done
echo "== rule-ish objects"; sf data query --query "SELECT Id, Name, Status, PromotionId FROM PromotionRule" --target-org target 2>&1 | head -12
sf data query --query "SELECT Id, DeveloperName, Status FROM ProcedurePlanDefinition LIMIT 1" --target-org target 2>&1 | tail -2
