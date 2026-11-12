#!/usr/bin/env bash
# Activate pricing procedure version 3, deactivate versions 2 and 1, sync pricing data, then run the Annual test.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
VERS="SELECT Id, ApiName, VersionNumber, IsActive FROM ExpressionSetVersion WHERE ExpressionSet.ApiName = 'RLM_DefaultPricingProcedure' ORDER BY VersionNumber"
upd() { sf data update record --sobject ExpressionSetVersion --record-id "$1" --values "IsActive=$2" --target-org target --json | jq -c --arg v "$3" '{version: $v, status, message}'; }
echo "before $(q "$VERS")"
for row in $(q "$VERS" | jq -r '.[] | "\(.Id)|\(.VersionNumber)"'); do id=${row%|*}; n=${row#*|}; [ "$n" = "3" ] && upd "$id" true "v3 activate"; done
for row in $(q "$VERS" | jq -r '.[] | "\(.Id)|\(.VersionNumber)"'); do id=${row%|*}; n=${row#*|}; [ "$n" != "3" ] && upd "$id" false "v$n deactivate"; done
echo "after $(q "$VERS")"
echo "sync pricing data: $(sf api request rest "$API/connect/core-pricing/sync/syncData" --target-org target 2>&1 | tr -d '\n ')"
sleep 20
./scripts/usage/pricing_place.sh
