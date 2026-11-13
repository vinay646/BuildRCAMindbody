#!/usr/bin/env bash
# Check-only deploys of pricing v5 with the floor output pointed at different line tags, to see which tags the
# List Price element accepts (diagnosis for "Specify a valid data type for the ListPrice variable").
set -uo pipefail
for TAG in MbFloorPrice MbBillingMonths MbHierarchyLocationCount ItemUnitCost__std RLM_Distributor_Unit_Price__c; do
  FLOOR_TAG=$TAG python3 scripts/build_pricing_v5.py > /dev/null
  sf project deploy start --dry-run --api-version "$ORG_API" --source-dir deploy/pricing-v5 --target-org target --wait 20 --json > r.json 2>&1 || true
  echo "$TAG => $(jq -r '.result.status // .name // "?"' r.json 2>/dev/null) $(jq -c '[.result.details.componentFailures? | if type=="array" then .[] elif . == null then empty else . end | .problem] , .message' r.json 2>/dev/null | tr -d '\n' | head -c 300)"
done
