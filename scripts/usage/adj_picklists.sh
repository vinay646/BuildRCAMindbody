#!/usr/bin/env bash
# READ ONLY: QuoteLinePriceAdjustment picklists + any manual adjustments in the org
sf sobject describe --sobject QuoteLinePriceAdjustment --target-org target --json | jq -c '.result.fields[] | select(.type=="picklist") | {name, values: [.picklistValues[] | select(.active) | .value]}'
sf data query --query "SELECT AdjustmentSource, AdjustmentType, COUNT(Id) n FROM QuoteLinePriceAdjustment GROUP BY AdjustmentSource, AdjustmentType" --target-org target 2>&1 | tail -10
