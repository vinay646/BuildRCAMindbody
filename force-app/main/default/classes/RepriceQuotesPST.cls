/**
 * Reprices quotes through the standard Place Sales Transaction Apex API (RevSalesTrxn.PlaceSalesTransactionExecutor):
 * PATCH the quote with no field changes, pricing preference Force and configuration Skip, so the pricing procedure and
 * the promotion engine run again and the results are saved; the bundle configuration is not touched.
 *
 * Called from the record-triggered flows MB Quote Coupon Code / MB Quote Line Coupon Code in the same save, so the
 * rep sees the new prices as soon as the save finishes. If the immediate reprice is not possible in that save (for
 * example the line editor's own pricing call is still running), it is rolled back and done by a queued job instead,
 * so the save never fails because of it.
 *
 * After the reprice the 0% "Quote coupon code" placeholders those flows add are deleted: the promotion engine has then
 * applied the coupon (its own promotion adjustment carries the code), and a placeholder is a Promotion adjustment
 * without a promotion, which the line editor's Promotions tab cannot show.
 *
 * Finally each line's Promotion Applied flag is set from its promotion adjustments: promotional lines are exempt from
 * the floor price check (Below Floor, PRC-18).
 */
public class RepriceQuotesPST {
    public static final String PLACEHOLDER = 'Quote coupon code';
    @TestVisible static Boolean running = false;

    public class RepriceException extends Exception {}

    @InvocableMethod(label='repriceQuotesPST' category='Quote' description='Reprices each quote (pricing Force) through Place Sales Transaction, now or, if that is not possible in this save, in a queued job.')
    public static void repriceQuotesPST(List<String> ids) {
        Set<String> quoteIds = new Set<String>();
        for (String id : ids) {
            if (String.isNotBlank(id)) {
                quoteIds.add(id);
            }
        }
        if (quoteIds.isEmpty() || running) {
            return;
        }
        Savepoint sp = Database.setSavepoint();
        try {
            running = true;
            reprice(quoteIds);
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.WARN, 'Immediate reprice not possible, queued instead: ' + e.getMessage());
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new RepriceJob(quoteIds));
            }
        } finally {
            running = false;
        }
    }

    /** Reprices each quote and deletes its coupon placeholders; throws when Place Sales Transaction reports an error. */
    public static void reprice(Set<String> quoteIds) {
        RevSalesTrxn.PricingPreferenceEnum pricingPreference = RevSalesTrxn.PricingPreferenceEnum.FORCE;
        // Pricing only: the configurator is skipped. Running it here (SYSTEM with rules and validation) made the line
        // editor flag the Accelerate bundle ("Select products from at least ... child groups") on repriced quotes.
        RevSalesTrxn.ConfigurationExecutionEnum configEnum = RevSalesTrxn.ConfigurationExecutionEnum.SKIP;
        RevSalesTrxn.ConfigurationOptionsInput config = new RevSalesTrxn.ConfigurationOptionsInput();

        for (String id : quoteIds) {
            RevSalesTrxn.RecordResource quoteRecord = new RevSalesTrxn.RecordResource(Quote.getSObjectType(), 'PATCH', id);
            RevSalesTrxn.RecordWithReferenceRequest quoteObject = new RevSalesTrxn.RecordWithReferenceRequest('refQuote', quoteRecord);
            List<RevSalesTrxn.RecordWithReferenceRequest> records = new List<RevSalesTrxn.RecordWithReferenceRequest>{ quoteObject };
            RevSalesTrxn.GraphRequest graph = new RevSalesTrxn.GraphRequest('myGraphId', records);
            Object response = RevSalesTrxn.PlaceSalesTransactionExecutor.execute(graph, pricingPreference, configEnum, config, null);
            Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(response));
            if (r != null && r.get('isSuccess') == false) {
                throw new RepriceException('Quote ' + id + ': ' + JSON.serialize(r.get('errorResponse')));
            }
        }
        deletePlaceholders(quoteIds);
        markPromotionLines(quoteIds);
    }

    /** Sets Quote Line Item > Promotion Applied: true when the line has a Promotion adjustment linked to a promotion. */
    public static void markPromotionLines(Set<String> quoteIds) {
        if (quoteIds.isEmpty()) {
            return;
        }
        Set<Id> promoted = new Set<Id>();
        for (QuoteLinePriceAdjustment a : [SELECT QuoteLineItemId FROM QuoteLinePriceAdjustment
                WHERE QuoteLineItem.QuoteId IN :quoteIds AND AdjustmentSource = 'Promotion' AND PriceAdjustmentCauseId != null]) {
            promoted.add(a.QuoteLineItemId);
        }
        List<QuoteLineItem> changed = new List<QuoteLineItem>();
        for (QuoteLineItem l : [SELECT Id, MB_Promotion_Applied__c FROM QuoteLineItem WHERE QuoteId IN :quoteIds]) {
            Boolean want = promoted.contains(l.Id);
            if (l.MB_Promotion_Applied__c != want) {
                changed.add(new QuoteLineItem(Id = l.Id, MB_Promotion_Applied__c = want));
            }
        }
        if (!changed.isEmpty()) {
            Database.update(changed, false);
        }
    }

    /** Deletes the coupon placeholders on the quotes' lines (Promotion, no promotion linked, description PLACEHOLDER). */
    public static void deletePlaceholders(Set<String> quoteIds) {
        if (quoteIds.isEmpty()) {
            return;
        }
        List<QuoteLinePriceAdjustment> rows = new List<QuoteLinePriceAdjustment>();
        for (QuoteLinePriceAdjustment a : [SELECT Id, Description FROM QuoteLinePriceAdjustment
                WHERE QuoteLineItem.QuoteId IN :quoteIds AND AdjustmentSource = 'Promotion'
                AND PriceAdjustmentCauseId = null AND CouponCode != null]) {
            if (a.Description == PLACEHOLDER) {
                rows.add(a);
            }
        }
        if (!rows.isEmpty()) {
            Database.delete(rows, false);
        }
    }

    /** Fallback when the reprice cannot run inside the save. */
    public class RepriceJob implements Queueable {
        private final Set<String> quoteIds;
        public RepriceJob(Set<String> quoteIds) {
            this.quoteIds = quoteIds;
        }
        public void execute(QueueableContext ctx) {
            reprice(quoteIds);
        }
    }
}
