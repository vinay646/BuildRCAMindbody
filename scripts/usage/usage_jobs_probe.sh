#!/usr/bin/env bash
# Read-only: inputs of the standard usage flows and the summary creation action
API="/services/data/v$ORG_API"
for a in flow/runtime_industries_usage__CreateSum flow/runtime_industries_usage__CreaUseSum flow/runtime_industries_usage__LiabSum flow/runtime_industries_usage__UseRateSum; do
  echo "$a $(sf api request rest "$API/actions/custom/$a" --target-org target 2>/dev/null | jq -c '{label, inputs: [.inputs[]? | {name, type, required}]}')"
done
echo "invokeSummaryCreationService $(sf api request rest "$API/actions/standard/invokeSummaryCreationService" --target-org target 2>/dev/null | jq -c '{label, inputs: [.inputs[]? | {name, type, required, description}]}')"
echo "invokeRatingService $(sf api request rest "$API/actions/standard/invokeRatingService" --target-org target 2>/dev/null | jq -c '{inputs: [.inputs[]? | {name, type, required}]}')"
