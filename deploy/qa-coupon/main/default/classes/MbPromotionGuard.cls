/**
 * MR-103: only the quote's own Coupon Code may discount a quote. Called (after commit) by the MB Quote Line Promotion
 * Guard flow whenever a Promotion price adjustment is created on a quote line, for example when a rep switches on a
 * promotion in the configurator's promotions panel without the coupon.
 * Removes every Promotion adjustment on the quote's lines that does not carry the quote's Coupon Code (all of them when
 * the quote has no code, or when the code does not qualify under MbCouponRules), then reprices the quote.
 * It never adds anything, so it cannot trigger itself again in a loop.
 */
public with sharing class MbPromotionGuard {

    @InvocableMethod(label='MB Remove promotions not from the quote coupon' description='Removes promotion discounts that do not belong to the quote Coupon Code, then reprices.')
    public static void guard(List<Id> quoteIds) {
        Set<Id> ids = new Set<Id>(quoteIds);
        ids.remove(null);
        if (ids.isEmpty()) {
            return;
        }
        List<QuoteLinePriceAdjustment> toDelete = new List<QuoteLinePriceAdjustment>();
        Set<String> reprice = new Set<String>();
        for (Quote q : [SELECT Id, Coupon_Code__c FROM Quote WHERE Id IN :ids]) {
            String code = q.Coupon_Code__c == null ? '' : q.Coupon_Code__c.trim().toUpperCase();
            Boolean eligible = String.isNotBlank(code) && MbCouponRules.check(q.Id, code) == null;
            for (QuoteLinePriceAdjustment a : [SELECT Id, CouponCode FROM QuoteLinePriceAdjustment
                    WHERE QuoteLineItem.QuoteId = :q.Id AND AdjustmentSource = 'Promotion']) {
                String aCode = a.CouponCode == null ? '' : a.CouponCode.trim().toUpperCase();
                if (!(eligible && aCode == code)) {
                    toDelete.add(a);
                    reprice.add(q.Id);
                }
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
            RepriceQuotesPST.repriceQuotesPST(new List<String>(reprice));
        }
    }
}
