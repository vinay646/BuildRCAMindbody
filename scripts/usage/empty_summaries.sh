#!/usr/bin/env bash
# Usage test: where the accumulation period comes from (usage resource -> billing policy)
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '.result.records // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
for o in UsageResource ProductUsageResource ProductUsageResourcePolicy UsageResourcePolicy BindingObjUsageRsrcPlcy UsageResourceBillingPolicy; do
  echo "== $o fields: $(rest GET /sobjects/$o/describe | jq -r '[.fields[] | select(.name | test("Polic|Period|Accum|Billing|Rating|Frequency"; "i")) | "\(.name)(\(.type)\(if .createable then ",c" else "" end)\(if .updateable then ",u" else "" end))"] | join(" ")')"
done
echo "== resources"
q "SELECT Id, Name, Code, Status FROM UsageResource WHERE Id IN ('1BRhm0000001aW5GAI','1BRhm0000001Sv9GAE','1BRhm0000001Sv8GAE')"
