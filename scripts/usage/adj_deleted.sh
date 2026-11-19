#!/usr/bin/env bash
# READ ONLY: adjustments (incl. deleted) on the failing test quotes 00000151 / 00000152.
set -uo pipefail
sf data query --all-rows --query "SELECT QuoteLineItem.Quote.QuoteNumber, QuoteLineItem.Product2.ProductCode, IsDeleted, AdjustmentValue, CouponCode, PriceAdjustmentCauseId, Description, CreatedDate, LastModifiedDate FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.Quote.QuoteNumber IN ('00000151','00000152') ORDER BY CreatedDate" --target-org target --json | jq -c '.result.records[]? | del(.attributes) | .QuoteLineItem |= {q: .Quote.QuoteNumber, p: .Product2.ProductCode}'
