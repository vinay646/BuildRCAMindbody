#!/usr/bin/env bash
# Read-only: QA usage set-up detail - resources and units, SMS policy, grants, rate cards and their price book links, entries
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
nn() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | with_entries(select(.value != null and (.key|test("Created|LastMod|System|Owner|attributes|Viewed|Referenced|IsDeleted")|not)))]'; }
echo "RES $(nn "SELECT FIELDS(ALL) FROM UsageResource WHERE Code IN ('MB_SMS_MSG','MB_MKT_FIRST','MB_PAY_TXN') LIMIT 5")"
echo "UOM $(q "SELECT Id, Name, UnitCode, UnitOfMeasureClass.Name FROM UnitOfMeasure WHERE Id IN (SELECT DefaultUnitOfMeasureId FROM UsageResource WHERE Code IN ('MB_SMS_MSG','MB_MKT_FIRST','MB_PAY_TXN'))")"
echo "PUR $(nn "SELECT FIELDS(ALL) FROM ProductUsageResource WHERE Product.ProductCode IN ('MB-SMS','MB-MKT','MB-PAY') LIMIT 5")"
echo "PURP $(nn "SELECT FIELDS(ALL) FROM ProductUsageResourcePolicy WHERE ProductUsageResource.Product.ProductCode IN ('MB-SMS','MB-MKT','MB-PAY') LIMIT 5")"
echo "BINDING $(q "SELECT Name, Product2.ProductCode, GrantBindingType FROM UsagePrdGrantBindingPolicy WHERE Product2.ProductCode IN ('MB-SMS','MB-MKT','MB-PAY','MB-ULT')")"
echo "RATECARDS $(nn "SELECT FIELDS(ALL) FROM RateCard LIMIT 20" | jq -c '[.[] | {Id, Name, Type}]')"
echo "RCE $(nn "SELECT FIELDS(ALL) FROM RateCardEntry WHERE Product.ProductCode IN ('MB-SMS','MB-MKT','MB-PAY') LIMIT 10")"
echo "PBRC $(q "SELECT RateCard.Name, PriceBook.Name, RateCardType FROM PriceBookRateCard")"
echo "USAGE PSM $(q "SELECT Product2.ProductCode, ProductSellingModel.Name FROM ProductSellingModelOption WHERE Product2.ProductCode IN ('MB-SMS','MB-MKT','MB-PAY')")"
echo "BILLING POLICIES $(q "SELECT Name, Status FROM UsageResourceBillingPolicy")"
