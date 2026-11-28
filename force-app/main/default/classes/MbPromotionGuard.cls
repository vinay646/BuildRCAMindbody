/**
 * MR-103: only the quote's own Coupon Code may discount a quote. Called (after commit) by the MB Quote Line Promotion
 * Guard flow whenever a Promotion price adjustment is created on a quote line, for example when a rep switches on a
 * promotion in the configurator's promotions panel without the coupon.
 * Removes every Promotion adjustment on the quote's lines that does not carry the quote's Coupon Code (all of them when
 * the quote has no code, or when the code does not qualify under MbCouponRules), then reprices the quote.
 * Promotions are exclusive, so switching one on can replace the coupon's own discount on a line: when something was
 * removed and the coupon still qualifies, every line without the coupon gets it back (0% placeholder carrying the
 * code) before the reprice. Nothing is added when nothing was removed, so the guard cannot loop.
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
        List<QuoteLinePriceAdjustment> toCreate = new List<QuoteLinePriceAdjustment>();
        Set<String> reprice = new Set<String>();
        for (Quote q : [SELECT Id, Coupon_Code__c FROM Quote WHERE Id IN :ids]) {
            String code = q.Coupon_Code__c == null ? '' : q.Coupon_Code__c.trim().toUpperCase();
            Boolean eligible = String.isNotBlank(code) && MbCouponRules.check(q.Id, code) == null;
            Map<Id, Boolean> lineHasCoupon = new Map<Id, Boolean>();
            for (QuoteLineItem l : [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id]) {
                lineHasCoupon.put(l.Id, false);
            }
            Boolean removed = false;
            for (QuoteLinePriceAdjustment a : [SELECT Id, QuoteLineItemId, CouponCode FROM QuoteLinePriceAdjustment
                    WHERE QuoteLineItem.QuoteId = :q.Id AND AdjustmentSource = 'Promotion']) {
                String aCode = a.CouponCode == null ? '' : a.CouponCode.trim().toUpperCase();
                if (eligible && aCode == code) {
                    lineHasCoupon.put(a.QuoteLineItemId, true);
                } else {
                    toDelete.add(a);
                    removed = true;
                }
            }
            if (!removed) {
                continue;
            }
            reprice.add(q.Id);
            if (eligible) {
                for (Id lineId : lineHasCoupon.keySet()) {
                    if (!lineHasCoupon.get(lineId)) {
                        toCreate.add(new QuoteLinePriceAdjustment(QuoteLineItemId = lineId, AdjustmentSource = 'Promotion',
                            AdjustmentType = 'AdjustmentPercentage', AdjustmentValue = 0, CouponCode = code,
                            Description = RepriceQuotesPST.PLACEHOLDER));
                    }
                }
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toCreate.isEmpty()) {
            insert toCreate;
        }
        if (!reprice.isEmpty()) {
            RepriceQuotesPST.repriceQuotesPST(new List<String>(reprice));
        }
    }
}
