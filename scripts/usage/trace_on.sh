#!/usr/bin/env bash
# CHANGES org setup (debug only): debug log trace flag on the admin user for 2 hours, to capture what the line editor and the coupon automation do.
set -uo pipefail
U=$(sf data query --query "SELECT Id FROM User WHERE Username = 'exploremore@rca.com'" --target-org target --json | jq -r '.result.records[0].Id')
DL=$(sf data query --use-tooling-api --query "SELECT Id FROM DebugLevel WHERE DeveloperName = 'MB_Coupon_Debug'" --target-org target --json | jq -r '.result.records[0].Id // empty')
if [ -z "$DL" ]; then
  DL=$(sf data create record --use-tooling-api --sobject DebugLevel --values "DeveloperName=MB_Coupon_Debug MasterLabel=MB_Coupon_Debug ApexCode=FINE ApexProfiling=NONE Callout=INFO Database=INFO System=DEBUG Validation=INFO Visualforce=NONE Workflow=FINE" --target-org target --json | jq -r '.result.id')
fi
for id in $(sf data query --use-tooling-api --query "SELECT Id FROM TraceFlag WHERE TracedEntityId = '$U'" --target-org target --json | jq -r '.result.records[]?.Id'); do
  sf data delete record --use-tooling-api --sobject TraceFlag --record-id "$id" --target-org target >/dev/null
done
S=$(date -u +%Y-%m-%dT%H:%M:%SZ); E=$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)
sf data create record --use-tooling-api --sobject TraceFlag --values "TracedEntityId=$U DebugLevelId=$DL LogType=USER_DEBUG StartDate=$S ExpirationDate=$E" --target-org target --json | jq -c '{status, id: .result.id, message}'
echo "trace on for $U until $E"
