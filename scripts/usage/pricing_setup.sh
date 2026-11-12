#!/usr/bin/env bash
# Single pricing procedure: retire MB_Pricing_Procedure, sync pricing data, set the Pulse demo location count.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '.result.records // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
VERS="SELECT Id, ApiName, VersionNumber, IsActive, StartDateTime, ExpressionSet.ApiName FROM ExpressionSetVersion WHERE ExpressionSet.ApiName IN ('RLM_DefaultPricingProcedure','MB_Pricing_Procedure') ORDER BY ApiName"
echo "== 1. versions before"; q "$VERS"
for id in $(sf data query --query "SELECT Id FROM ExpressionSetVersion WHERE ExpressionSet.ApiName = 'MB_Pricing_Procedure' AND IsActive = true" --target-org target --json | jq -r '.result.records[]?.Id'); do
  echo "deactivate $id:"; sf data update record --sobject ExpressionSetVersion --record-id "$id" --values "IsActive=false" --target-org target --json | jq -c '{status, message}'
done
echo "== 2. delete MB_Pricing_Procedure"
sf project deploy start --api-version "$ORG_API" --manifest manifest/delete-mb-pricing-procedure/package.xml \
  --post-destructive-changes manifest/delete-mb-pricing-procedure/destructiveChanges.xml \
  --target-org target --ignore-warnings --wait 30 --json > del.json 2>&1 || true
jq -c '{status: .result.status, errors: [.result.details.componentFailures? | if type=="array" then .[] else . end | select(.!=null) | .problem]}' del.json 2>/dev/null || head -c 800 del.json
echo "== versions after"; q "$VERS"
echo "== 3. sync pricing data"
for p in /connect/core-pricing/sync/syncData /connect/core-pricing/syncPricingData; do echo "POST $p"; rest POST "$p" '{}' | head -c 600; echo; done
echo "== 4. Pulse demo location count"
for id in $(sf data query --query "SELECT Id FROM Account WHERE Name = 'Pulse Fitness Brands'" --target-org target --json | jq -r '.result.records[]?.Id'); do
  sf data update record --sobject Account --record-id "$id" --values "Active_Location_Count__c=12" --target-org target --json | jq -c '{status, message}'
done
q "SELECT Name, Active_Location_Count__c FROM Account WHERE Name LIKE 'Pulse%' AND Active_Location_Count__c != null"
