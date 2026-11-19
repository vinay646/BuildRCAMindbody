#!/usr/bin/env bash
# READ ONLY: what a working promotion looks like on a quote line (price adjustments with a promotion or coupon).
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
echo "== QuoteLinePriceAdjustment fields $(rest GET /sobjects/QuoteLinePriceAdjustment/describe | jq -c '[.fields[]? | {n: .name, t: .type, c: .createable, pick: ([.picklistValues[]?.value]|join(","))}]')"
echo "== Adjustments with a promotion or coupon (most recent 15)"
q "SELECT FIELDS(STANDARD) FROM QuoteLinePriceAdjustment WHERE PromotionId != null OR CouponCode != null ORDER BY CreatedDate DESC LIMIT 15" \
  | jq -c '.[]? | with_entries(select(.value != null and (.key|test("Created|LastModified|SystemModstamp|IsDeleted|Owner|CurrencyIsoCode")|not)))'
echo "== Their quotes"
q "SELECT QuoteLineItem.Quote.QuoteNumber, QuoteLineItem.Quote.CreatedBy.Name, QuoteLineItem.Product2.ProductCode, QuoteLineItem.ListPrice, QuoteLineItem.NetUnitPrice, CreatedDate FROM QuoteLinePriceAdjustment WHERE PromotionId != null OR CouponCode != null ORDER BY CreatedDate DESC LIMIT 15"
echo "== Promotions $(q "SELECT Id, Name, IsActive, IsAutomatic, PromotionCode, StartDate, EndDate, RuleLibraryId FROM Promotion")"
echo "== Promotion targets for the new promotions $(q "SELECT Promotion.Name, TargetType, TargetId, AdjustmentType, AdjustmentPercent, AdjustmentAmount FROM PromotionTarget WHERE Promotion.Name IN ('NewPromo','TodayOffer')")"
