#!/usr/bin/env bash
# READ ONLY: everything quote-related created or changed today after 10:40 UTC.
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
T=2026-11-19T10:40:00Z
echo "== quotes changed after $T"
q "SELECT QuoteNumber, Name, Coupon_Code__c, CalculationStatus, CreatedDate, LastModifiedDate, Status, OpportunityId, LineItemCount, TotalPrice FROM Quote WHERE LastModifiedDate > $T AND (NOT Name LIKE 'COUPON%')" | jq -c '.[]?'
echo "== quote lines created/changed after $T (non-test quotes)"
q "SELECT Quote.QuoteNumber, Product2.ProductCode, ListPrice, NetUnitPrice, CreatedDate, LastModifiedDate FROM QuoteLineItem WHERE LastModifiedDate > $T AND (NOT Quote.Name LIKE 'COUPON%') ORDER BY LastModifiedDate" | jq -c '.[]?'
echo "== price adjustments created after $T (non-test quotes)"
q "SELECT QuoteLineItem.Quote.QuoteNumber, QuoteLineItem.Product2.ProductCode, AdjustmentSource, AdjustmentValue, CouponCode, PriceAdjustmentCauseId, Description, CreatedDate FROM QuoteLinePriceAdjustment WHERE CreatedDate > $T AND (NOT QuoteLineItem.Quote.Name LIKE 'COUPON%') ORDER BY CreatedDate" | jq -c '.[]?'
echo "== deleted quote lines (recycle bin) after $T"
sf data query --query "SELECT Quote.QuoteNumber, Product2.ProductCode, IsDeleted, LastModifiedDate FROM QuoteLineItem WHERE IsDeleted = true AND LastModifiedDate > $T" --all-rows --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'
echo "== flow definitions active versions"
sf data query --use-tooling-api --query "SELECT ApiName, ActiveVersionId, LatestVersionId, TriggerType, ProcessType FROM FlowDefinitionView WHERE ApiName LIKE 'MB_Quote%Coupon%'" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)]'
