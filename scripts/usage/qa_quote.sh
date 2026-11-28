#!/usr/bin/env bash
# Read-only: one QA quote (QN) - header, lines, promotion adjustments
QN=${QN:-00000288}
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
echo "QUOTE $(q "SELECT Id, Name, Status, Coupon_Code__c, RLM_TermMonths__c, StartDate, Prior_system__c, Opportunity.Prior_System__c, Account.Name, TotalPrice, GrandTotal, LastModifiedDate FROM Quote WHERE QuoteNumber = '$QN'" | jq -c '.[0] | .Opportunity |= (.Prior_System__c) | .Account |= .Name')"
QID=$(q "SELECT Id FROM Quote WHERE QuoteNumber = '$QN'" | jq -r '.[0].Id')
q "SELECT Product2.ProductCode, Quantity, BillingFrequency, SubscriptionTerm, PricingTermCount, ListPrice, NetUnitPrice, TotalPrice, MB_Promotion_Applied__c, MB_Price_Before_Promotion__c, LastModifiedDate FROM QuoteLineItem WHERE QuoteId = '$QID' AND (ListPrice > 0 OR Product2.ProductCode LIKE 'MB-PAY%')" | jq -r '.[] | "LINE \(.Product2.ProductCode) qty \(.Quantity) \(.BillingFrequency) term \(.SubscriptionTerm) PTC \(.PricingTermCount) list \(.ListPrice) net \(.NetUnitPrice) total \(.TotalPrice) promo \(.MB_Promotion_Applied__c) before \(.MB_Price_Before_Promotion__c) mod \(.LastModifiedDate[11:19])"'
echo "ADJ $(q "SELECT QuoteLineItem.Product2.ProductCode, AdjustmentSource, AdjustmentType, AdjustmentValue, CouponCode, PriceAdjustmentCauseId, CreatedDate FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = '$QID' AND AdjustmentSource != 'System'" | jq -c '[.[] | [.QuoteLineItem.Product2.ProductCode, .AdjustmentSource, .AdjustmentValue, .CouponCode, (.PriceAdjustmentCauseId != null), .CreatedDate[11:19]]]')"
echo "PROMOS $(q "SELECT Name, IsActive, StartDateTime, EndDateTime FROM Promotion" | jq -c '[.[] | [.Name, .IsActive, .StartDateTime[0:10], .EndDateTime[0:10]]]')"
echo "COUPONS $(q "SELECT CouponCode, Status, Promotion.Name FROM Coupon" 2>&1 | head -c 400)"
