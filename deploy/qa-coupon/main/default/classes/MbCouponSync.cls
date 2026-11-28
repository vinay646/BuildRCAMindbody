/**
 * MR-103: keeps a quote's coupon in step with its lines. Called by the MB Quote Line Coupon Code flow when a line
 * is added to a quote that has a Coupon Code, so the coupon can be entered before any product.
 *  - The quote qualifies now (MbCouponRules, all conditions): every line without this coupon gets a 0% Promotion
 *    placeholder carrying the code, and the quote is repriced, which applies the promotion to its eligible products.
 *  - It does not qualify yet (for example Starter added but Payments not yet): this coupon's promotion adjustments
 *    are removed (if any) and the code waits on the quote; the next line added checks again. No error is raised.
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
            if (String.isBlank(code)) {
                continue;
            }
            Boolean eligible = MbCouponRules.check(q.Id, code) == null;
            Map<Id, List<QuoteLinePriceAdjustment>> byLine = new Map<Id, List<QuoteLinePriceAdjustment>>();
            for (QuoteLineItem l : [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id]) {
                byLine.put(l.Id, new List<QuoteLinePriceAdjustment>());
            }
            for (QuoteLinePriceAdjustment a : [SELECT Id, QuoteLineItemId FROM QuoteLinePriceAdjustment
                    WHERE QuoteLineItem.QuoteId = :q.Id AND AdjustmentSource = 'Promotion' AND CouponCode = :code]) {
                byLine.get(a.QuoteLineItemId).add(a);
            }
            Boolean changed = false;
            for (Id lineId : byLine.keySet()) {
                List<QuoteLinePriceAdjustment> existing = byLine.get(lineId);
                if (eligible && existing.isEmpty()) {
                    toCreate.add(new QuoteLinePriceAdjustment(QuoteLineItemId = lineId, AdjustmentSource = 'Promotion',
                        AdjustmentType = 'AdjustmentPercentage', AdjustmentValue = 0, CouponCode = code,
                        Description = RepriceQuotesPST.PLACEHOLDER));
                    changed = true;
                } else if (!eligible && !existing.isEmpty()) {
                    toDelete.addAll(existing);
                    changed = true;
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
