#!/usr/bin/env bash
# Which context definitions in the org contain a ProductCategoryHierarchy node? (Connect API, standard + custom)
set -uo pipefail
API="/services/data/v$ORG_API"
rest() { sf api request rest "$API$1" --target-org target 2>&1; }
L=$(rest "/connect/context-definitions?pageSize=200")
echo "DEFS $(echo "$L" | jq -c '[.contextDefinitions[]? | {n: .developerName, id: .contextDefinitionId, std: .isStandard}]' 2>/dev/null | head -c 3000)"
[ -z "$(echo "$L" | jq -r '.contextDefinitions[0].developerName // empty' 2>/dev/null)" ] && echo "RAW $(echo "$L" | tr -d '\n' | head -c 800)"
for id in $(echo "$L" | jq -r '.contextDefinitions[]? | .contextDefinitionId'); do
  D=$(rest "/connect/context-definitions/$id")
  N=$(echo "$D" | jq -r '.developerName // .name // "?"')
  H=$(echo "$D" | tr -d '\n' | grep -o '"[A-Za-z_]*[Hh]ierarch[A-Za-z_]*"' | sort -u | tr '\n' ' ')
  echo "$N: ${H:-none}"
done
