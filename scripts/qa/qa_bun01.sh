#!/usr/bin/env bash
# READ-ONLY QA for MB-BUN-01 Tier bundles with included features.
set -uo pipefail
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
MBP="SELECT Id FROM Product2 WHERE ProductCode LIKE 'MB-%'"
echo "== IDS"; raw "SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'MB-%'"
echo "== GROUPS"; raw "SELECT Id, Name, ParentProductId, MinBundleComponents, MaxBundleComponents, Sequence FROM ProductComponentGroup WHERE ParentProductId IN ($MBP)"
echo "== COMPONENTS"; raw "SELECT ParentProductId, ChildProductId, ProductComponentGroupId, IsComponentRequired, IsDefaultComponent, QuantityScaleMethod, IsQuantityEditable, DoesBundlePriceIncludeChild, Quantity, MinQuantity, MaxQuantity FROM ProductRelatedComponent WHERE ParentProductId IN ($MBP)"
echo "== FEATURE PRICES"; raw "SELECT Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode, UnitPrice, IsActive FROM PricebookEntry WHERE Product2.ProductCode LIKE 'MB-F-%'"
