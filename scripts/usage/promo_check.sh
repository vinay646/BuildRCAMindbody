#!/usr/bin/env bash
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
echo "PROMOS $(q "SELECT FIELDS(STANDARD) FROM Promotion LIMIT 10" | jq -c '[.[]? | with_entries(select(.value != null and (.key|test("Created|LastModified|System|IsDeleted|LastViewed|LastReferenced|Owner")|not)))]' | head -c 3000)"
echo "TARGETS $(q "SELECT Promotion.Name, TargetId, TargetType, AdjustmentType, AdjustmentPercent, AdjustmentAmount FROM PromotionTarget LIMIT 10" | head -c 1500)"
echo "COUPONS $(q "SELECT FIELDS(STANDARD) FROM Coupon LIMIT 5" | head -c 1500)"
echo "EXPRESSION SETS $(q "SELECT ApiName, Name, UsageType FROM ExpressionSet ORDER BY UsageType")"
echo "PLAN SECTIONS $(q "SELECT FIELDS(STANDARD) FROM ProcedurePlanSection LIMIT 10" | jq -c '[.[]? | {DeveloperName, SectionType, Sequence, ResolutionType}]')"
echo "QUOTE promo fields $(rest GET /sobjects/Quote/describe | jq -c '[.fields[] | select(.name|test("Promo|Coupon";"i")) | .name]')"
echo "QLI promo fields $(rest GET /sobjects/QuoteLineItem/describe | jq -c '[.fields[] | select(.name|test("Promo|Coupon|Floor";"i")) | .name]')"
echo "SOBJECTS promo $(rest GET /sobjects | jq -c '[.sobjects[] | select(.name|test("Promo|Coupon";"i")) | .name]')"
echo "ACTIONS promo $(rest GET /actions/standard | jq -c '[.actions[]? | select(.name|test("romot|oupon";"i")) | .name]')"
echo "CONNECT gpm $(rest GET /connect/global-promotions-management | head -c 600)"
echo "PRICING SETTINGS"
rm -rf rs; mkdir rs; sf project retrieve start --api-version "$ORG_API" --metadata "Settings:IndustriesPricing" --metadata "Settings:RevenueManagement" --metadata "Settings:GlobalPromotionsManagement" --target-org target --target-metadata-dir rs --unzip --wait 10 --json > rs.json 2>&1 || true
for f in $(find rs -type f -name '*.settings*'); do echo "-- $f"; sed -e 's/^[[:space:]]*//' "$f" | tr -d '\n' | head -c 2000; echo; done
jq -r '.result.messages // [] | .[] | "WARN \(.problem)"' rs.json 2>/dev/null | head -5
echo "FLOOR BOOK $(q "SELECT Pricebook2.Name, Product2.ProductCode, CurrencyIsoCode, UnitPrice FROM PricebookEntry WHERE Pricebook2.Name = 'Mindbody Floor Prices' AND CurrencyIsoCode = 'USD'")"
