#!/usr/bin/env bash
# Read-only: Mindbody usage set-up in the org (usage resources, product usage resources/policies, grants, rate card entries for MB-SMS / MB-MKT / MB-PAY)
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
echo "RESOURCES $(q "SELECT Code, Status FROM UsageResource WHERE Code LIKE 'MB-%'" | jq -c '[.[] | [.Code, .Status]]')"
echo "PRODUCT USAGE $(q "SELECT Product.ProductCode, UsageResource.Code, Status FROM ProductUsageResource WHERE Product.ProductCode LIKE 'MB-%'" | jq -c '[.[] | [.Product.ProductCode, .UsageResource.Code, .Status]]')"
echo "POLICIES $(q "SELECT ProductUsageResource.Product.ProductCode FROM ProductUsageResourcePolicy WHERE ProductUsageResource.Product.ProductCode LIKE 'MB-%'" | jq -c '[.[].ProductUsageResource.Product.ProductCode]')"
echo "GRANTS $(q "SELECT Product.ProductCode, Quantity FROM ProductUsageGrant WHERE Product.ProductCode LIKE 'MB-%'" | jq -c '[.[] | [.Product.ProductCode, .Quantity]]')"
echo "RATES $(q "SELECT RateCard.Name, Product.ProductCode, Rate, Status FROM RateCardEntry WHERE Product.ProductCode LIKE 'MB-%'" | jq -c '[.[] | [.RateCard.Name, .Product.ProductCode, .Rate, .Status]]')"
echo "MODEL $(q "SELECT ProductCode, UsageModelType FROM Product2 WHERE ProductCode IN ('MB-SMS','MB-MKT','MB-PAY')" | jq -c '[.[] | [.ProductCode, .UsageModelType]]')"
