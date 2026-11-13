#!/usr/bin/env bash
# READ-ONLY QA for MB-PRD-06 Usage products: MB-PAY, MB-MKT, MB-SMS.
set -uo pipefail
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes) | with_entries(select(.value != null and (.key|test("^(IsDeleted|SystemModstamp|LastViewedDate|LastReferencedDate|LastModifiedById|CreatedById|OwnerId|CreatedDate|LastModifiedDate)$")|not)))] else {error: .message} end'; }
U="('MB-PAY','MB-MKT','MB-SMS')"
echo "== PRODUCTS"; raw "SELECT ProductCode, Name, IsActive, Family, QuantityUnitOfMeasure, UsageModelType, BillingPolicyId, BillingPolicy.Name, TaxPolicyId FROM Product2 WHERE ProductCode IN $U"
echo "== CATEGORY"; raw "SELECT Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name FROM ProductCategoryProduct WHERE Product.ProductCode IN $U"
echo "== SELLING MODELS"; raw "SELECT Product2.ProductCode, ProductSellingModel.Name, ProductSellingModel.SellingModelType FROM ProductSellingModelOption WHERE Product2.ProductCode IN $U"
echo "== PRICES"; raw "SELECT Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode, UnitPrice, ProductSellingModel.Name, IsActive FROM PricebookEntry WHERE Product2.ProductCode IN $U ORDER BY Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode"
echo "== BILLING POLICIES"; raw "SELECT Id, Name, Status, DefaultBillingTreatment.Name, BillingTreatmentSelection FROM BillingPolicy"
echo "== BILLING TREATMENTS"; raw "SELECT Id, Name, Status, BillingPolicy.Name, LegalEntity.Name, ExcludeFromBilling FROM BillingTreatment"
echo "== BILLING TREATMENT ITEMS"; raw "SELECT BillingTreatment.Name, Name, BillingType, Percentage, ProcessingOrder FROM BillingTreatmentItem LIMIT 50"
echo "== LEGAL ENTITIES"; raw "SELECT Id, Name, Status FROM LegalEntity"
echo "== USAGE RESOURCES"; raw "SELECT Product.ProductCode, UsageResource.Name, UsageResource.Code, Status FROM ProductUsageResource WHERE Product.ProductCode IN $U"
echo "== RATE CARD ENTRIES"; raw "SELECT RateCard.Name, Product.ProductCode, UsageResource.Name, Rate, RateUnitOfMeasureName, RateCardType, Status FROM RateCardEntry WHERE Product.ProductCode IN $U OR UsageProduct.ProductCode IN $U"
