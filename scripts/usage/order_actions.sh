#!/usr/bin/env bash
# READ ONLY: inputs/outputs of the standard Q2C actions
for a in createOrderFromQuote createContract createOrUpdateAssetFromOrder initiateRenewal initiateAmendment; do
  sf api request rest "/services/data/v$ORG_API/actions/standard/$a" --target-org target 2>/dev/null | jq -c --arg a $a '{a: $a, in: [.inputs[] | "\(.name):\(.type)\(if .required then "*" else "" end)"], out: [.outputs[] | "\(.name):\(.type)"]}'
done
