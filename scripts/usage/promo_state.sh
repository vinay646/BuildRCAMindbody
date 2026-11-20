#!/usr/bin/env bash
# READ ONLY: every promotion, its coupons, rule configuration (eligibility, rewards, duration) and qualifiers.
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
echo "== promotions"
q "SELECT Id, Name, IsActive, IsAutomatic, StartDateTime, EndDateTime, RuleLibraryId, PromotionCode, LastModifiedDate, LastModifiedBy.Name FROM Promotion ORDER BY CreatedDate" | jq -c '.[]'
echo "== coupons"
q "SELECT CouponCode, Status, Promotion.Name, StartDateTime, EndDateTime FROM Coupon ORDER BY Promotion.Name" | jq -c '.[] | {c: .CouponCode, s: .Status, p: .Promotion.Name, from: .StartDateTime, to: .EndDateTime}'
echo "== configuration of rule-library promotions"
for row in $(q "SELECT Id, Name FROM Promotion WHERE RuleLibraryId != null" | jq -r '.[] | "\(.Id)|\(.Name)"'); do
  id=${row%%|*}; n=${row#*|}
  echo "--- $n"; q "SELECT PromotionConfiguration FROM Promotion WHERE Id = '$id'" | jq -r '.[0].PromotionConfiguration' | jq -c '.steps | {eligibility: .promotionEligibility, rules: [.configureTemplate.rules[]? | {template: .templateName, rule: .ruleName, rewards: .rewardConfiguration}]}' 2>/dev/null | head -c 2500; echo
done
echo "== qualifiers / segments / limits"
for o in PromotionQualifier PromotionSegment PromotionLimit PromotionMarketSegment PromotionTier PromotionProduct PromotionProductCategory; do echo "   $o: $(q "SELECT FIELDS(STANDARD) FROM $o LIMIT 20" | jq -c '[.[]? | with_entries(select(.value != null and (.key|test("Created|LastModified|System|IsDeleted|LastViewed|LastReferenced|Owner|Currency|^Id$")|not)))]' | head -c 800)"; done
echo "== promotion rule templates available"
q "SELECT DeveloperName, MasterLabel FROM PromotionRuleTemplate" 2>/dev/null | head -c 1500; echo
