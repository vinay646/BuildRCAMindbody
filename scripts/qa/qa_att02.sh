#!/usr/bin/env bash
# READ-ONLY QA for MB-ATT-02 Selling models.
set -uo pipefail
raw() { sf data query --query "$1" --target-org target --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
echo "== MODELS"; raw "SELECT Name, SellingModelType, PricingTerm, PricingTermUnit, Status FROM ProductSellingModel WHERE Name IN ('Evergreen Monthly','Term Monthly','One-Time','Term Annual')"
echo "== OPTIONS"; raw "SELECT Product2.ProductCode, ProductSellingModel.Name FROM ProductSellingModelOption WHERE Product2.ProductCode LIKE 'MB-%' ORDER BY Product2.ProductCode"
