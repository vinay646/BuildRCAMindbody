#!/usr/bin/env bash
# Read-only: MR-101 contract term discount tiers in QA, all plans and currencies
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
S=$(q "SELECT Id FROM PriceAdjustmentSchedule WHERE Name = 'Contract Term Discount'" | jq -r '.[0].Id')
q "SELECT Product2.ProductCode, CurrencyIsoCode, LowerBound, UpperBound, TierValue FROM PriceAdjustmentTier WHERE PriceAdjustmentScheduleId = '$S' ORDER BY Product2.ProductCode, CurrencyIsoCode, LowerBound" | jq -r 'group_by(.Product2.ProductCode + " " + .CurrencyIsoCode)[] | "\(.[0].Product2.ProductCode) \(.[0].CurrencyIsoCode): " + ([.[] | "\(.LowerBound)-\(.UpperBound)=\(.TierValue)%"] | join(", "))'
