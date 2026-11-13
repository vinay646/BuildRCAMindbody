#!/usr/bin/env bash
# Activate pricing procedure version 4 (promotions), deactivate version 3, sync pricing data.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
VERS="SELECT Id, ApiName, VersionNumber, IsActive FROM ExpressionSetVersion WHERE ExpressionSet.ApiName = 'RLM_DefaultPricingProcedure' ORDER BY VersionNumber"
upd() { sf data update record --sobject ExpressionSetVersion --record-id "$1" --values "IsActive=$2" --target-org target --json | jq -c --arg v "$3" '{version: $v, status, message}'; }
echo "before $(q "$VERS" | jq -c '[.[] | {VersionNumber, IsActive}]')"
for row in $(q "$VERS" | jq -r '.[] | "\(.Id)|\(.VersionNumber)"'); do id=${row%|*}; n=${row#*|}; [ "$n" = "4" ] && upd "$id" true "v4 activate"; done
for row in $(q "$VERS" | jq -r '.[] | select(.IsActive == true) | "\(.Id)|\(.VersionNumber)"'); do id=${row%|*}; n=${row#*|}; [ "$n" != "4" ] && upd "$id" false "v$n deactivate"; done
echo "after $(q "$VERS" | jq -c '[.[] | {VersionNumber, IsActive}]')"
echo "sync pricing data: $(sf api request rest "$API/connect/core-pricing/sync/syncData" --target-org target 2>&1 | tr -d '\n ')"
