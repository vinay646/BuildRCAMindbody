#!/usr/bin/env bash
# Tags of the standard CartDetailGetEligiblePromotion context (the rule library mapping names come from it).
set -uo pipefail
API="/services/data/v$ORG_API"
rest() { sf api request rest "$API$1" --target-org target 2>&1; }
ID=CartDetailGetEligiblePromotion__stdctx
D=$(rest "/connect/context-definitions/$ID")
echo "DEF $(echo "$D" | jq -c '{activeVersionId, versions: .contextDefinitionVersionList}' | head -c 1500)"
AV=$(echo "$D" | jq -r '.activeVersionId // empty')
for p in "/connect/context-definitions/$ID/versions/$AV" "/connect/context-definitions/$ID/versions" "/connect/context-definitions/$ID/context-nodes" "/connect/context-definitions/$ID/version/$AV/context-nodes"; do
  R=$(rest "$p")
  echo "== $p ($(echo "$R" | wc -c) bytes)"
  echo "   hierarchy strings: $(echo "$R" | tr -d '\n' | grep -o '"[A-Za-z_]*[Hh]ierarch[A-Za-z_]*"' | sort -u | tr '\n' ' ')"
  echo "   head: $(echo "$R" | tr -d '\n' | head -c 400)"
done
