#!/usr/bin/env bash
# READ ONLY: current state of test quotes 00000151 / 00000152 (did the delayed async reprice ever run?).
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
for n in 00000151 00000152; do
  echo "== $n $(q "SELECT Coupon_Code__c, LastModifiedDate, CalculationStatus FROM Quote WHERE QuoteNumber = '$n'")"
  q "SELECT Product2.ProductCode, NetUnitPrice, LastModifiedDate FROM QuoteLineItem WHERE Quote.QuoteNumber = '$n'" | jq -c '.[] | {p: .Product2.ProductCode, net: .NetUnitPrice, mod: .LastModifiedDate}'
  q "SELECT QuoteLineItem.Product2.ProductCode, AdjustmentValue, CouponCode, PriceAdjustmentCauseId, Description, CreatedDate FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.Quote.QuoteNumber = '$n'" | jq -c '.[]?'
done
echo "== deleted adjustments on them"
sf data query --all-rows --query "SELECT QuoteLineItemId, IsDeleted, AdjustmentValue, CouponCode, Description, CreatedDate, LastModifiedDate FROM QuoteLinePriceAdjustment WHERE IsDeleted = true AND LastModifiedDate = TODAY ORDER BY LastModifiedDate DESC LIMIT 20" --target-org target --json | jq -c '.result.records[]? | del(.attributes)'
