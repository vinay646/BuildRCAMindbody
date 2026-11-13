#!/usr/bin/env bash
# READ-ONLY QA for MB-PRD-04 Services: MB-TAM, MB-IMP, MB-DCV, MB-CON.
set -uo pipefail
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes) | with_entries(select(.value != null and (.key|test("^(IsDeleted|SystemModstamp|LastViewedDate|LastReferencedDate|LastModifiedById|CreatedById|OwnerId|CreatedDate|LastModifiedDate)$")|not)))] else {error: .message} end'; }
S="('MB-TAM','MB-IMP','MB-DCV','MB-CON')"
echo "== PRODUCTS"; raw "SELECT ProductCode, Name, IsActive, Type, Family, IsSoldOnlyWithOtherProds, QuantityUnitOfMeasure, UnitOfMeasureId, UnitOfMeasure.Name, Description FROM Product2 WHERE ProductCode IN $S"
echo "== SELLING MODEL OPTIONS"; raw "SELECT Product2.ProductCode, ProductSellingModel.Name, ProductSellingModel.SellingModelType, ProductSellingModel.PricingTerm, ProductSellingModel.PricingTermUnit, IsDefault FROM ProductSellingModelOption WHERE Product2.ProductCode IN $S"
echo "== PRICE BOOK ENTRIES"; raw "SELECT Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode, UnitPrice, ProductSellingModel.Name, IsActive FROM PricebookEntry WHERE Product2.ProductCode IN $S ORDER BY Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode"
echo "== CATEGORY"; raw "SELECT Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name FROM ProductCategoryProduct WHERE Product.ProductCode IN $S"
