#!/usr/bin/env bash
# READ-ONLY QA for MR-71 MB-CAT-02 Add-ons only inside a tier.
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== add-ons and features: sold only with other products"
q "SELECT ProductCode, Name, IsActive, IsSoldOnlyWithOtherProds FROM Product2 WHERE (ProductCode LIKE 'MB-F-%' OR ProductCode IN ('MB-APP','MB-APP-SET','MB-AIC')) ORDER BY ProductCode" | jq -r '.[] | "\(.ProductCode) | \(.Name) | active=\(.IsActive) | soldOnlyWithOthers=\(.IsSoldOnlyWithOtherProds)"'
echo "== category assignments of add-ons and features (expected none)"
q "SELECT Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name FROM ProductCategoryProduct WHERE Product.ProductCode LIKE 'MB-F-%' OR Product.ProductCode IN ('MB-APP','MB-APP-SET','MB-AIC')"
echo "== where each add-on sits in a bundle"
q "SELECT ParentProduct.ProductCode, ProductComponentGroup.Name, ChildProduct.ProductCode, IsComponentRequired, IsDefaultComponent, Quantity, QuantityScaleMethod, IsQuantityEditable FROM ProductRelatedComponent WHERE ChildProduct.ProductCode IN ('MB-APP','MB-APP-SET','MB-F-AIC','MB-AIC') ORDER BY ParentProduct.ProductCode" | jq -r '.[] | "\(.ParentProduct.ProductCode) > \(.ProductComponentGroup.Name // "-") > \(.ChildProduct.ProductCode) | required=\(.IsComponentRequired) default=\(.IsDefaultComponent) qty=\(.Quantity) \(.QuantityScaleMethod) editable=\(.IsQuantityEditable)"'
echo "== features per tier (count)"
q "SELECT ParentProduct.ProductCode p, COUNT(Id) n FROM ProductRelatedComponent WHERE ChildProduct.ProductCode LIKE 'MB-F-%' GROUP BY ParentProduct.ProductCode"
echo "== distinct included features"
q "SELECT ChildProduct.ProductCode c FROM ProductRelatedComponent WHERE ChildProduct.ProductCode LIKE 'MB-F-%' AND ChildProduct.ProductCode != 'MB-F-AIC' GROUP BY ChildProduct.ProductCode"
echo "== changes to these products since 13 Nov"
q "SELECT ProductCode, LastModifiedDate, LastModifiedBy.Name FROM Product2 WHERE (ProductCode LIKE 'MB-F-%' OR ProductCode IN ('MB-APP','MB-APP-SET')) AND LastModifiedDate >= 2026-11-13T18:25:00Z"
