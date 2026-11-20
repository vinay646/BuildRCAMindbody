#!/usr/bin/env bash
# READ ONLY: Volume Discount Entries lookup inputs and the Price Adjustment Tier data behind it
echo "== Price_Adjustment_Tier_Decision_Table parameters"
sf data query --query "SELECT FieldName, Usage, Operator, Sequence FROM DecisionTableParameter WHERE DecisionTable.DeveloperName = 'Price_Adjustment_Tier_Decision_Table' ORDER BY Usage, Sequence" --target-org target 2>&1 | tail -14
echo "== schedules"
sf data query --query "SELECT Id, Name, ApiName, IsActive, AdjustmentMethod, ScheduleType, Pricebook2Id FROM PriceAdjustmentSchedule" --target-org target 2>&1 | tail -15
echo "== tiers (schedule, product, selling model, currency, bounds, type, value)"
sf data query --query "SELECT PriceAdjustmentSchedule.Name, Product2.ProductCode, ProductSellingModel.Name, CurrencyIsoCode, LowerBound, UpperBound, TierType, TierValue, EffectiveFrom, EffectiveTo FROM PriceAdjustmentTier ORDER BY PriceAdjustmentSchedule.Name, Product2.ProductCode, CurrencyIsoCode, LowerBound" --target-org target --json | jq -r '.result.records[] | [.PriceAdjustmentSchedule.Name, .Product2.ProductCode, .ProductSellingModel.Name, .CurrencyIsoCode, .LowerBound, .UpperBound, .TierType, .TierValue, .EffectiveFrom, .EffectiveTo] | map(tostring) | join(" | ")'
