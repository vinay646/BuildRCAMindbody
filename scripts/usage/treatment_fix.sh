#!/usr/bin/env bash
set -uo pipefail
T=$(sf data query --query "SELECT Id FROM BillingTreatment WHERE Name = 'Mindbody Billing Treatment - Advance'" --target-org target --json | jq -r '.result.records[0].Id')
echo "update: $(sf data update record --sobject BillingTreatment --record-id "$T" --values "CanChangeBillingFrequency=false" --target-org target --json | jq -c '{status, message}')"
echo "now: $(sf data query --query "SELECT Name, Status, CanChangeBillingFrequency FROM BillingTreatment WHERE Id = '$T'" --target-org target --json | jq -c '.result.records')"
./scripts/usage/pricing_place.sh
