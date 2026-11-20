#!/usr/bin/env bash
# READ ONLY: categories holding the plan bundles
sf data query --query "SELECT ProductCategory.Name, ProductCategoryId, Product.ProductCode FROM ProductCategoryProduct WHERE Product.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT')" --target-org target 2>&1 | head -20
