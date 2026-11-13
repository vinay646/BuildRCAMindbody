#!/usr/bin/env bash
# Check-only deploys of pricing v5 with the floor output pointed at different line tags, to see which tags the
# List Price element accepts (diagnosis for "Specify a valid data type for the ListPrice variable").
set -uo pipefail
for TAG in MbFloorPrice MbBillingMonths MbHierarchyLocationCount ItemUnitCost__std RLM_Distributor_Unit_Price__c; do
  FLOOR_TAG=$TAG python3 scripts/build_pricing_v5.py > /dev/null
  R=$(sf project deploy validate --api-version "$ORG_API" --source-dir deploy/pricing-v5 --target-org target --wait 20 --json 2>/dev/null)
  echo "$TAG => $(echo "$R" | jq -r '.result.status // .status') $(echo "$R" | jq -c '[.result.details.componentFailures? | if type=="array" then .[] else . end | .problem?] // .message' | head -c 300)"
done
