#!/usr/bin/env bash
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
LE=$(q "SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - US'" | jq -r '.[0].Id')
T=$(q "SELECT Id FROM BillingTreatment WHERE Name = 'Mindbody Billing Treatment - Advance'" | jq -r '.[0].Id')
P=$(q "SELECT Id FROM BillingPolicy WHERE Name = 'Mindbody Billing Policy'" | jq -r '.[0].Id')
echo "treatment legal entity: $(sf data update record --sobject BillingTreatment --record-id "$T" --values "LegalEntityId=$LE" --target-org target --json | jq -c '{status, message}')"
echo "policy selection: $(sf data update record --sobject BillingPolicy --record-id "$P" --values "BillingTreatmentSelection=LegalEntity" --target-org target --json | jq -c '{status, message}')"
echo "now $(q "SELECT Name, BillingTreatmentSelection, DefaultBillingTreatmentId FROM BillingPolicy WHERE Id = '$P'") $(q "SELECT Name, LegalEntityId, CanChangeBillingFrequency FROM BillingTreatment WHERE Id = '$T'")"
VARIANTS=legal ./scripts/usage/pricing_place.sh
