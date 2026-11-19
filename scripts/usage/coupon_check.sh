#!/usr/bin/env bash
# READ ONLY: how coupon codes fit promotions in this org (objects, fields, records, API).
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
desc() { rest GET /sobjects/$1/describe | jq -c --arg r "$2" '[.fields[]? | select(.name|test($r;"i")) | {n: .name, t: .type, c: .createable, ref: (.referenceTo|join(",")), pick: ([.picklistValues[]?.value]|join(","))}]'; }
echo "== SOBJECTS (promo/coupon) $(rest GET /sobjects | jq -c '[.sobjects[] | select(.name|test("Promo|Coupon";"i")) | .name]')"
echo "== Promotion fields $(desc Promotion '.')"
echo "== Coupon fields $(desc Coupon '.')"
echo "== PromotionCoupon/CouponCode objects:"; for o in CouponCodeRedemption PromotionCoupon PromotionCouponCode CouponCode; do echo "   $o $(rest GET /sobjects/$o/describe | jq -c '[.fields[]?.name] // .' | head -c 400)"; done
echo "== Quote coupon/promo fields $(desc Quote 'promo|coupon')"
echo "== QLI coupon/promo fields $(desc QuoteLineItem 'promo|coupon')"
echo "== QLI price adjustment coupon fields $(desc QuoteLineItemPriceAdjustment 'promo|coupon|source')"
echo "== PROMOTIONS $(q "SELECT Id, Name, IsActive, StartDateTime, EndDateTime, FIELDS(STANDARD) FROM Promotion LIMIT 20" 2>/dev/null | head -c 3000)"
echo "== COUPONS $(q "SELECT FIELDS(ALL) FROM Coupon LIMIT 20" | head -c 2000)"
echo "== PROMO TARGETS $(q "SELECT Promotion.Name, TargetId, TargetType, AdjustmentType, AdjustmentPercent, AdjustmentAmount FROM PromotionTarget LIMIT 20" | head -c 1500)"
echo "== CONNECT GPM root $(rest GET /connect/global-promotions-management | head -c 800)"
echo "== ACTIONS $(rest GET /actions/standard | jq -c '[.actions[]? | select(.name|test("romot|oupon";"i")) | .name]')"
echo "== CONTEXT (standard) coupon attrs: $(q "SELECT Id, DeveloperName FROM ContextDefinition LIMIT 0" ) "
