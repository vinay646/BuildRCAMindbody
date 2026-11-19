#!/usr/bin/env bash
# READ ONLY: the most recent non-test quotes (last 60 min), their lines and adjustments, and debug logs mentioning the coupon flows / reprice.
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
SINCE=$(date -u -d '-60 min' +%Y-%m-%dT%H:%M:%SZ)
for row in $(q "SELECT Id, QuoteNumber FROM Quote WHERE LastModifiedDate > $SINCE AND (NOT Name LIKE 'COUPON%') AND (NOT Name LIKE 'BILLFREQ%') ORDER BY LastModifiedDate DESC LIMIT 3" | jq -r '.[] | "\(.Id)|\(.QuoteNumber)"'); do
  id=${row%|*}; n=${row#*|}
  echo "== quote $n $(q "SELECT Coupon_Code__c, CalculationStatus, CreatedDate, LastModifiedDate FROM Quote WHERE Id = '$id'")"
  q "SELECT Id, Product2.ProductCode, ListPrice, NetUnitPrice, CreatedDate, LastModifiedDate FROM QuoteLineItem WHERE QuoteId = '$id'" | jq -c '.[] | {id: .Id, p: .Product2.ProductCode, net: .NetUnitPrice, created: .CreatedDate, mod: .LastModifiedDate}'
  echo "   adjustments:"
  q "SELECT QuoteLineItem.Product2.ProductCode, AdjustmentValue, CouponCode, PriceAdjustmentCauseId, Description, CreatedDate FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = '$id'" | jq -c '.[]? | {p: .QuoteLineItem.Product2.ProductCode, v: .AdjustmentValue, c: .CouponCode, cause: .PriceAdjustmentCauseId, d: .Description, t: .CreatedDate}'
  echo "   deleted adjustments:"
  sf data query --all-rows --query "SELECT QuoteLineItem.Product2.ProductCode, AdjustmentValue, CouponCode, Description, CreatedDate, LastModifiedDate FROM QuoteLinePriceAdjustment WHERE IsDeleted = true AND QuoteLineItem.QuoteId = '$id'" --target-org target --json | jq -c '.result.records[]? | {p: .QuoteLineItem.Product2.ProductCode, v: .AdjustmentValue, c: .CouponCode, d: .Description, t: .CreatedDate, del: .LastModifiedDate}'
done
echo "== debug logs since $SINCE with coupon flows / reprice"
for lid in $(sf data query --use-tooling-api --query "SELECT Id FROM ApexLog WHERE StartTime > $SINCE ORDER BY StartTime" --target-org target --json | jq -r '.result.records[].Id'); do
  body=$(sf api request rest "/services/data/v$ORG_API/tooling/sobjects/ApexLog/$lid/Body" --target-org target 2>/dev/null)
  if echo "$body" | grep -q "Coupon Code\|RepriceQuotesPST"; then
    echo "--- log $lid $(echo "$body" | head -1 | cut -c1-80)"
    echo "$body" | grep -E "FLOW_START_INTERVIEW_BEGIN.*Coupon|RepriceQuotesPST|FLOW_ELEMENT_BEGIN|FLOW_ELEMENT_ERROR|FLOW_START_SCHEDULED|EXCEPTION|FATAL|Op:(Insert|Delete).*QuoteLinePriceAdjustment|USER_DEBUG|FLOW_INTERVIEW_FINISHED_LIMIT|SCHEDULED" | sed -E 's/^[0-9:.]+ \([0-9]+\)\|//' | cut -c1-220 | head -40
  fi
done
