#!/usr/bin/env bash
# CHANGES org cache: refreshes the pricing decision tables after price adjustment tier changes (standard action refreshDecisionTable)
API="/services/data/v$ORG_API"
ins=$(sf api request rest "$API/actions/standard/refreshDecisionTable" --target-org target 2>/dev/null | jq -c '[.inputs[] | {name, type, required}]'); echo "inputs: $ins"
n=$(echo "$ins" | jq -r '.[0].name')
for dn in Price_Adjustment_Tier_Decision_Table Contract_Pricing_Volume_Tiers; do
  id=$(sf data query --query "SELECT Id FROM DecisionTable WHERE DeveloperName = '$dn'" --target-org target --json | jq -r '.result.records[0].Id')
  v=$id; echo "$n" | grep -qi 'name' && v=$dn
  echo "== $dn: $(sf api request rest "$API/actions/standard/refreshDecisionTable" --method POST --body "{\"inputs\":[{\"$n\":\"$v\"}]}" --target-org target 2>&1 | tr -d '\n' | head -c 300)"
done
