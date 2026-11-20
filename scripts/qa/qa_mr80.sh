#!/usr/bin/env bash
# READ-ONLY QA for MR-80 MB-BUN-01 Tier bundles with included features.
set -uo pipefail
q() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== tier products"
q "SELECT ProductCode, Name, Type, ConfigureDuringSale, IsActive FROM Product2 WHERE ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT')" | jq -r '.[] | "   \(.ProductCode) | \(.Name) | type=\(.Type) | configure=\(.ConfigureDuringSale) | active=\(.IsActive)"'
echo "== components per tier"
q "SELECT ParentProduct.ProductCode, ProductComponentGroup.Name, ChildProduct.ProductCode, ChildProduct.Name, IsComponentRequired, IsDefaultComponent, Quantity, QuantityScaleMethod, IsQuantityEditable, DoesBundlePriceIncludeChild FROM ProductRelatedComponent WHERE ParentProduct.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT') ORDER BY ParentProduct.ProductCode, ProductComponentGroup.Name, ChildProduct.ProductCode" | jq -r '.[] | "   \(.ParentProduct.ProductCode) | \(.ProductComponentGroup.Name) | \(.ChildProduct.ProductCode) \(.ChildProduct.Name) | req=\(.IsComponentRequired) def=\(.IsDefaultComponent) qty=\(.Quantity) \(.QuantityScaleMethod) edit=\(.IsQuantityEditable) inPrice=\(.DoesBundlePriceIncludeChild)"'
echo "== feature prices"
q "SELECT Product2.ProductCode, Pricebook2.Name, UnitPrice FROM PricebookEntry WHERE Product2.ProductCode LIKE 'MB-F-%' AND Product2.ProductCode != 'MB-F-AIC' AND UnitPrice != 0 AND IsActive = true"
echo "== component groups min/max"
q "SELECT ParentProduct.ProductCode, Name, MinBundleComponents, MaxBundleComponents FROM ProductComponentGroup WHERE ParentProduct.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT')"
