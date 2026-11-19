/**
 * Reprices quotes through the standard Place Sales Transaction Apex API (RevSalesTrxn.PlaceSalesTransactionExecutor):
 * PATCH the quote with no field changes and pricing preference Force, so the pricing procedure (and the promotion
 * engine) run again and the results are saved. Called from record-triggered flows after a price-impacting change,
 * e.g. MB Quote Coupon Code / MB Quote Line Coupon Code (Run Asynchronously path, after the save commits).
 * After the reprice, the 0% "Quote coupon code" placeholders those flows add are deleted: the promotion engine has
 * then applied the coupon (its own promotion adjustment carries the code), and a placeholder is a Promotion
 * adjustment without a promotion, which the line editor's Promotions tab cannot show.
 */
public class RepriceQuotesPST {
    public static final String PLACEHOLDER = 'Quote coupon code';

    @InvocableMethod(label='repriceQuotesPST' category='Quote' description='Reprices each quote (pricing Force) through Place Sales Transaction.')
    public static void repriceQuotesPST(List<String> ids) {
        RevSalesTrxn.PricingPreferenceEnum pricingPreference = RevSalesTrxn.PricingPreferenceEnum.FORCE;
        RevSalesTrxn.ConfigurationExecutionEnum configEnum = RevSalesTrxn.ConfigurationExecutionEnum.SYSTEM;
        RevSalesTrxn.ConfigurationOptionsInput config = new RevSalesTrxn.ConfigurationOptionsInput();
        config.addDefaultConfiguration = true;
        config.executeConfigurationRules = true;
        config.validateAmendRenewCancel = true;
        config.validateProductCatalog = true;

        // one reprice per quote, even when several lines of the same quote ask for it in one transaction
        Set<String> seen = new Set<String>();
        for (String id : ids) {
            if (String.isBlank(id) || !seen.add(id)) {
                continue;
            }
            RevSalesTrxn.RecordResource quoteRecord = new RevSalesTrxn.RecordResource(Quote.getSObjectType(), 'PATCH', id);
            RevSalesTrxn.RecordWithReferenceRequest quoteObject = new RevSalesTrxn.RecordWithReferenceRequest('refQuote', quoteRecord);

            List<RevSalesTrxn.RecordWithReferenceRequest> records = new List<RevSalesTrxn.RecordWithReferenceRequest>();
            records.add(quoteObject);

            RevSalesTrxn.GraphRequest graph = new RevSalesTrxn.GraphRequest('myGraphId', records);
            RevSalesTrxn.PlaceSalesTransactionExecutor.execute(graph, pricingPreference, configEnum, config, null);
        }
        deletePlaceholders(seen);
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
}
