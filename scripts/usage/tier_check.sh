#!/usr/bin/env bash
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
echo "DT $(q "SELECT Id, DeveloperName, Status, SourceObject, ConditionType, ConditionCriteria FROM DecisionTable WHERE DeveloperName = 'Price_Adjustment_Tier_Decision_Table'")"
echo "DT PARAMS $(q "SELECT FieldName, Usage, Operator, Sequence FROM DecisionTableParameter WHERE DecisionTable.DeveloperName = 'Price_Adjustment_Tier_Decision_Table' ORDER BY Sequence")"
echo "TIERS ULT 11-50 $(q "SELECT Name, PriceAdjustmentSchedule.Name, ProductSellingModel.Name, CurrencyIsoCode, LowerBound, UpperBound, TierValue, EffectiveFrom, EffectiveTo FROM PriceAdjustmentTier WHERE Product2.ProductCode = 'MB-ULT' AND LowerBound = 11")"
echo "TIERS COUNT BY SCHEDULE $(q "SELECT PriceAdjustmentSchedule.Name n, CurrencyIsoCode c, COUNT(Id) k FROM PriceAdjustmentTier WHERE Product2.ProductCode = 'MB-ULT' GROUP BY PriceAdjustmentSchedule.Name, CurrencyIsoCode")"
echo "OTHER TIERS ON ULT $(q "SELECT PriceAdjustmentSchedule.Name, PriceAdjustmentSchedule.IsActive, COUNT(Id) k FROM PriceAdjustmentTier WHERE Product2.ProductCode = 'MB-ULT' GROUP BY PriceAdjustmentSchedule.Name, PriceAdjustmentSchedule.IsActive")"
echo "SCHEDULES $(q "SELECT Id, Name, IsActive, ScheduleType, CurrencyIsoCode FROM PriceAdjustmentSchedule")"
