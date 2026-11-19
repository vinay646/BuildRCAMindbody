#!/usr/bin/env bash
# READ ONLY: compare the UI-created promotion adjustment with the automation's, and related records the UI may create.
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
REF=5mbhm0000000QddAAE
echo "== UI record $REF (all fields)"
q "SELECT FIELDS(ALL) FROM QuoteLinePriceAdjustment WHERE Id = '$REF' LIMIT 1" | jq '.[0]'
LINE=$(q "SELECT QuoteLineItemId FROM QuoteLinePriceAdjustment WHERE Id = '$REF'" | jq -r '.[0].QuoteLineItemId')
echo "== its line and quote"
q "SELECT Id, Quote.QuoteNumber, Quote.Coupon_Code__c, Product2.ProductCode, ListPrice, NetUnitPrice, CreatedDate FROM QuoteLineItem WHERE Id = '$LINE'" | jq -c '.[]'
echo "== all adjustments on that line"
q "SELECT FIELDS(ALL) FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = '$LINE' LIMIT 20" | jq -c '.[] | with_entries(select(.value != null))'
echo "== automation-created promotion adjustments on test quotes (latest 3)"
q "SELECT FIELDS(ALL) FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.Quote.Name LIKE 'COUPON-FLOW%' AND PriceAdjustmentCauseId != null ORDER BY CreatedDate DESC LIMIT 3" | jq -c '.[] | with_entries(select(.value != null))'
T=$(q "SELECT CreatedDate FROM QuoteLinePriceAdjustment WHERE Id = '$REF'" | jq -r '.[0].CreatedDate')
echo "== records created around $T"
for o in CouponCodeRedemption PromotionLimitUsage PromotionPartyUsage PromotionExecutionEvalGrp PromotionExecEvalGrpItem; do
  echo "-- $o $(q "SELECT FIELDS(STANDARD) FROM $o WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 5" | jq -c '[.[]? | with_entries(select(.value != null and (.key|test("LastModified|System|IsDeleted|Owner|LastViewed|LastReferenced")|not)))]' | head -c 1500)"
done
echo "== describe QuoteLinePriceAdjustment (all fields incl. read-only)"
sf sobject describe --sobject QuoteLinePriceAdjustment --target-org target --json | jq -c '[.result.fields[] | {n: .name, t: .type, c: .createable, ref: (.referenceTo|join(","))}]'
