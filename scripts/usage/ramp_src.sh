#!/usr/bin/env bash
# READ ONLY: source of the sample ramp schedule classes.
set -uo pipefail
for c in RLM_RampScheduleFlowAction RLM_RampScheduleRequest RLM_RampScheduleService RLM_RampScheduleValidator; do
  echo "################ $c"
  sf data query --use-tooling-api --query "SELECT Body FROM ApexClass WHERE Name = '$c'" --target-org target --json | jq -r '.result.records[0].Body'
done
