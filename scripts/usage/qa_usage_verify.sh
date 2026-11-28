#!/usr/bin/env bash
# Read-only: verifies the QA usage set-up after the build
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
echo "UNITS $(q "SELECT Code, DefaultUnitOfMeasure.Name, Status FROM UsageResource WHERE Code IN ('MB_SMS_MSG','MB_MKT_FIRST','MB_PAY_TXN')" | jq -c '[.[] | [.Code, .DefaultUnitOfMeasure.Name, .Status]]')"
echo "POLICIES $(q "SELECT ProductUsageResource.Product.ProductCode, UsageAggregationPolicy.Name FROM ProductUsageResourcePolicy WHERE ProductUsageResource.Product.ProductCode IN ('MB-SMS','MB-MKT','MB-PAY')" | jq -c '[.[] | [.ProductUsageResource.Product.ProductCode, .UsageAggregationPolicy.Name]]')"
echo "BINDINGS $(q "SELECT Product2.ProductCode, GrantBindingType FROM UsagePrdGrantBindingPolicy WHERE Product2.ProductCode IN ('MB-SMS','MB-MKT','MB-PAY')" | jq -c '[.[] | [.Product2.ProductCode, .GrantBindingType]]')"
echo "RATES $(q "SELECT RateCard.Name, RateCardType, Product.ProductCode, Rate, Status, DefaultUnitOfMeasure.Name FROM RateCardEntry WHERE Product.ProductCode IN ('MB-SMS','MB-MKT','MB-PAY')" | jq -c '[.[] | [.RateCardType, .Product.ProductCode, .Rate, .Status, .DefaultUnitOfMeasure.Name]]')"
echo "PRICEBOOKS $(q "SELECT PriceBook.Name FROM PriceBookRateCard WHERE RateCard.Name = 'Mindbody SMS Overage Rate Card'" | jq -c '[.[].PriceBook.Name]')"
