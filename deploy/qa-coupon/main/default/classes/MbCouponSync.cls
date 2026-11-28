/**
 * MR-103: keeps a quote's coupon in step with its lines. Called by the MB Quote Line Coupon Code flow when a line
 * is added to a quote that has a Coupon Code, so the coupon can be entered before any product.
 *  - The quote qualifies now (MbCouponRules, all conditions): every line without this coupon gets a 0% Promotion
 *    placeholder carrying the code, and the quote is repriced, which applies the promotion to its eligible products.
 *  - It does not qualify yet (for example Starter added but Payments not yet): this coupon's promotion adjustments
 *    are removed (if any) and the code waits on the quote; the next line added checks again. No error is raised.
 *  - Only the quote's coupon may discount the quote: any other promotion on its lines (for example one switched on in
 *    the configurator's promotions panel, with no coupon) is removed, and with no Coupon Code every promotion is removed.
 *    Also called by the MB Quote Line Promotion Guard flow when a promotion adjustment lands on a line.
 */
public with sharing class MbCouponSync {

    @InvocableMethod(label='MB Sync quote coupon' description='Applies the quote Coupon Code to all lines when the quote qualifies, else removes it from the lines, and reprices.')
    public static void sync(List<Id> quoteIds) {
        Set<Id> ids = new Set<Id>(quoteIds);
        ids.remove(null);
        if (ids.isEmpty()) {
            return;
        }
        List<QuoteLinePriceAdjustment> toCreate = new List<QuoteLinePriceAdjustment>();
        List<QuoteLinePriceAdjustment> toDelete = new List<QuoteLinePriceAdjustment>();
        List<String> reprice = new List<String>();
        for (Quote q : [SELECT Id, Coupon_Code__c FROM Quote WHERE Id IN :ids]) {
            String code = q.Coupon_Code__c == null ? '' : q.Coupon_Code__c.trim().toUpperCase();
            Boolean eligible = String.isNotBlank(code) && MbCouponRules.check(q.Id, code) == null;
            Map<Id, Boolean> lineHasCoupon = new Map<Id, Boolean>();
            for (QuoteLineItem l : [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id]) {
                lineHasCoupon.put(l.Id, false);
            }
            Boolean changed = false;
            for (QuoteLinePriceAdjustment a : [SELECT Id, QuoteLineItemId, CouponCode FROM QuoteLinePriceAdjustment
                    WHERE QuoteLineItem.QuoteId = :q.Id AND AdjustmentSource = 'Promotion']) {
                String aCode = a.CouponCode == null ? '' : a.CouponCode.trim().toUpperCase();
                if (eligible && aCode == code) {
                    lineHasCoupon.put(a.QuoteLineItemId, true);   // the quote's own coupon: keep
                } else {
                    toDelete.add(a);                               // another promotion, or the coupon does not qualify
                    changed = true;
                }
            }
            if (eligible) {
                for (Id lineId : lineHasCoupon.keySet()) {
                    if (!lineHasCoupon.get(lineId)) {
                        toCreate.add(new QuoteLinePriceAdjustment(QuoteLineItemId = lineId, AdjustmentSource = 'Promotion',
                            AdjustmentType = 'AdjustmentPercentage', AdjustmentValue = 0, CouponCode = code,
                            Description = RepriceQuotesPST.PLACEHOLDER));
                        changed = true;
                    }
                }
            }
            if (changed) {
                reprice.add(q.Id);
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toCreate.isEmpty()) {
            insert toCreate;
        }
        if (!reprice.isEmpty()) {
            RepriceQuotesPST.repriceQuotesPST(reprice);
        }
    }
}
