#!/usr/bin/env bash
# READ-ONLY QA for epic MB- Catalogs (MR-65): MR-70 catalog and categories, MR-71 add-ons only inside a tier.
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes) | with_entries(select(.value != null and (.key|test("^(IsDeleted|SystemModstamp|LastViewedDate|LastReferencedDate|LastModifiedById|CreatedById|OwnerId|CreatedDate)$")|not)))] // .message'; }
echo "== CATALOGS"; q "SELECT FIELDS(ALL) FROM ProductCatalog LIMIT 50"
echo "== CATEGORIES"; q "SELECT FIELDS(ALL) FROM ProductCategory LIMIT 200"
echo "== CATEGORY PRODUCTS"; sf data query --query "SELECT ProductCategory.Name, ProductCategory.Catalog.Name, Product.ProductCode, Product.Name, Product.IsActive, Product.IsSoldOnlyWithOtherProds FROM ProductCategoryProduct LIMIT 2000" --target-org target --json | jq -c '[.result.records[]? | {cat: .ProductCategory.Name, catalog: .ProductCategory.Catalog.Name, code: .Product.ProductCode, name: .Product.Name, active: .Product.IsActive, bundleOnly: .Product.IsSoldOnlyWithOtherProds}] | map(select(.catalog != null and (.catalog|test("QuantumBit|Quantum";"i")|not)))'
echo "== PRODUCTS (non-QuantumBit)"; sf data query --query "SELECT Id, ProductCode, Name, IsActive, Type, IsSoldOnlyWithOtherProds, ConfigureDuringSale, BasedOn.Name, Family, CreatedDate FROM Product2 WHERE (NOT ProductCode LIKE 'QB-%') ORDER BY CreatedDate DESC LIMIT 300" --target-org target --json | jq -c '[.result.records[]? | {code: .ProductCode, name: .Name, active: .IsActive, type: .Type, bundleOnly: .IsSoldOnlyWithOtherProds, cls: .BasedOn.Name, family: .Family, created: .CreatedDate[0:10]}]'
echo "== PRODUCT COUNT BY CREATED DAY"; q "SELECT DAY_ONLY(CreatedDate) d, COUNT(Id) n FROM Product2 GROUP BY DAY_ONLY(CreatedDate) ORDER BY DAY_ONLY(CreatedDate) DESC LIMIT 15"
echo "== CLASSIFICATIONS"; q "SELECT Id, Name, Code, Status FROM ProductClassification LIMIT 100"
raw() { sf data query --query "$1" --target-org target --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes) | with_entries(select(.value != null and (.key|test("^(IsDeleted|SystemModstamp|LastViewedDate|LastReferencedDate|LastModifiedById|CreatedById|OwnerId|CreatedDate|LastModifiedDate|CurrencyIsoCode)$")|not)))] else {error: .message} end'; }
MBP="SELECT Id FROM Product2 WHERE ProductCode LIKE 'MB-%'"
echo "== MB PRODUCT IDS"; raw "SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'MB-%'"
echo "== COMPONENT GROUPS"; raw "SELECT FIELDS(ALL) FROM ProductComponentGroup WHERE ParentProductId IN ($MBP) LIMIT 200"
echo "== BUNDLE COMPONENTS"; raw "SELECT FIELDS(ALL) FROM ProductRelatedComponent WHERE ParentProductId IN ($MBP) LIMIT 200"
