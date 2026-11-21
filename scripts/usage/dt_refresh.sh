#!/usr/bin/env bash
# CHANGES org cache: refreshes the pricing decision tables after price adjustment tier changes (tries the Connect API and the standard action)
API="/services/data/v$ORG_API"
for dn in Price_Adjustment_Tier_Decision_Table Contract_Pricing_Volume_Tiers; do
  id=$(sf data query --query "SELECT Id FROM DecisionTable WHERE DeveloperName = '$dn'" --target-org target --json | jq -r '.result.records[0].Id')
  echo "== $dn $id"
  for p in "connect/business-rules/decision-table/refresh/$id" "connect/business-rules/decision-table/$id/refresh"; do
    r=$(sf api request rest "$API/$p" --method POST --body '{"type":"full"}' --target-org target 2>&1 | tr -d '\n' | head -c 250); echo "$p => $r"
    echo "$r" | grep -qi 'error' || break
  done
done
sf api request rest "$API/actions/standard" --target-org target 2>/dev/null | grep -o '"name" *: *"[^"]*"' | grep -i 'decision\|refresh'
