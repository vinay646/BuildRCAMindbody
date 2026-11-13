#!/usr/bin/env bash
# Standard pricing data sync (refreshes pricing's cached lookups and context).
set -uo pipefail
echo "sync pricing data: $(sf api request rest "/services/data/v$ORG_API/connect/core-pricing/sync/syncData" --target-org target 2>&1 | tr -d '\n ')"
