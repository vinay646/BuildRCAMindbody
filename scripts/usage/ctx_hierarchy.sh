#!/usr/bin/env bash
# Which context definitions have a ProductCategoryHierarchy node, and is a standard upgrade available for ours?
set -uo pipefail
API="/services/data/v$ORG_API"
rest() { sf api request rest "$API$1" --target-org target 2>&1; }
L=$(rest "/connect/context-definitions?pageSize=200")
echo "DEFS $(echo "$L" | jq -c '[.contextDefinitionList[]? | {n: .developerName, id: .contextDefinitionId, type: .definitionType, base: .baseReference, upgrade: .isUpgradeAvailable, active: .isActive}]')"
for id in $(echo "$L" | jq -r '.contextDefinitionList[]? | .contextDefinitionId'); do
  D=$(rest "/connect/context-definitions/$id")
  N=$(echo "$D" | jq -r '.developerName // "?"')
  H=$(echo "$D" | tr -d '\n' | grep -o '"[A-Za-z_]*[Hh]ierarch[A-Za-z_]*"' | sort -u | tr '\n' ' ')
  echo "$N: hierarchy names: ${H:-none}; keys: $(echo "$D" | jq -c 'keys' 2>/dev/null | head -c 300)"
  for v in $(echo "$D" | jq -r '.contextDefinitionVersionList[]?.contextDefinitionVersionId' 2>/dev/null | head -3); do
    V=$(rest "/connect/context-definitions/$id/versions/$v" 2>/dev/null)
    echo "   version $v hierarchy: $(echo "$V" | tr -d '\n' | grep -o '"[A-Za-z_]*[Hh]ierarch[A-Za-z_]*"' | sort -u | tr '\n' ' ') nodes: $(echo "$V" | jq -c '[.. | objects | select(has("nodeId") or has("contextNodeId")) | (.name // .title // .developerName)] | unique | length' 2>/dev/null)"
  done
done
