#!/usr/bin/env bash
# Rule library version active, then deactivate/reactivate the Mindbody promotions so they are evaluated against it.
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
V=$(q "SELECT Id, Status FROM RuleLibraryVersion WHERE ApiName = 'RLM_RuleLibrary_V1'"); echo "RULE LIBRARY VERSION $V"
VID=$(echo "$V" | jq -r '.[0].Id'); [ "$(echo "$V" | jq -r '.[0].Status')" != "Active" ] && echo "activate: $(sf data update record --sobject RuleLibraryVersion --record-id "$VID" --values "Status=Active" --target-org target --json | jq -c '{status, message}')"
for p in LAUNCH3 SWITCH50 GROW2; do
  id=$(q "SELECT Id FROM Promotion WHERE Name = '$p'" | jq -r '.[0].Id')
  off=$(sf data update record --sobject Promotion --record-id "$id" --values "IsActive=false" --target-org target --json | jq -c '{status, message}')
  on=$(sf data update record --sobject Promotion --record-id "$id" --values "IsActive=true" --target-org target --json | jq -c '{status, message}')
  echo "$p off $off on $on"
done
echo "PROMOS $(q "SELECT Name, IsActive, IsAutomatic FROM Promotion")"
echo "RULE LIBRARY VERSION $(q "SELECT ApiName, Status FROM RuleLibraryVersion WHERE ApiName = 'RLM_RuleLibrary_V1'")"
