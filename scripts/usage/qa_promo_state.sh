#!/usr/bin/env bash
# READ ONLY: promotions / coupon automation pieces in this org
echo "promotions: $(sf data query --query "SELECT Name, IsActive, RuleLibraryId FROM Promotion" --target-org target --json | jq -c '[.result.records[] | {Name, IsActive, lib: (.RuleLibraryId != null)}]')"
echo "coupons: $(sf data query --query "SELECT CouponCode, Promotion.Name, Status FROM Coupon" --target-org target --json | jq -c '[.result.records[] | {c: .CouponCode, p: .Promotion.Name, s: .Status}]')"
echo "Quote.Coupon_Code__c: $(sf sobject describe --sobject Quote --target-org target --json | jq -r '[.result.fields[] | select(.name|test("coupon";"i")) | .name] | join(",")')"
echo "classes: $(sf data query --use-tooling-api --query "SELECT Name FROM ApexClass WHERE Name IN ('RepriceQuotesPST','MbCouponRules','RepriceQuotesPSTTest')" --target-org target --json | jq -r '[.result.records[].Name] | join(",")')"
echo "coupon flows: $(sf data query --query "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName LIKE '%oupon%' OR ApiName LIKE '%romo%' OR ApiName LIKE '%eprice%'" --target-org target --json | jq -c '[.result.records[] | {ApiName, IsActive}]')"
echo "promotion adjustments on lines: $(sf data query --query "SELECT COUNT() FROM QuoteLinePriceAdjustment WHERE AdjustmentSource = 'Promotion' AND PriceAdjustmentCauseId != null" --target-org target --json | jq -r .result.totalSize)"
sf data query --query "SELECT QuoteLineItem.Quote.QuoteNumber, QuoteLineItem.Product2.ProductCode, AdjustmentValue, CouponCode, CreatedDate FROM QuoteLinePriceAdjustment WHERE AdjustmentSource = 'Promotion' AND PriceAdjustmentCauseId != null ORDER BY CreatedDate DESC LIMIT 5" --target-org target 2>&1 | tail -8
