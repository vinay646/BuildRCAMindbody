// Quote 00000146 (COUPON-BUNDLE test, Accelerate bundle): what does a reprice return with configuration SYSTEM + validation, vs SKIP? Rolled back.
Quote qt = [SELECT Id FROM Quote WHERE QuoteNumber = '00000146' LIMIT 1];
for (String mode : new List<String>{ 'SYSTEM', 'SKIP' }) {
    Savepoint sp = Database.setSavepoint();
    RevSalesTrxn.ConfigurationOptionsInput config = new RevSalesTrxn.ConfigurationOptionsInput();
    if (mode == 'SYSTEM') {
        config.addDefaultConfiguration = true; config.executeConfigurationRules = true;
        config.validateAmendRenewCancel = true; config.validateProductCatalog = true;
    }
    RevSalesTrxn.RecordResource rec = new RevSalesTrxn.RecordResource(Quote.getSObjectType(), 'PATCH', qt.Id);
    RevSalesTrxn.GraphRequest graph = new RevSalesTrxn.GraphRequest('g', new List<RevSalesTrxn.RecordWithReferenceRequest>{ new RevSalesTrxn.RecordWithReferenceRequest('refQuote', rec) });
    Object resp = RevSalesTrxn.PlaceSalesTransactionExecutor.execute(graph, RevSalesTrxn.PricingPreferenceEnum.FORCE,
        mode == 'SYSTEM' ? RevSalesTrxn.ConfigurationExecutionEnum.SYSTEM : RevSalesTrxn.ConfigurationExecutionEnum.SKIP, config, null);
    System.debug(LoggingLevel.ERROR, mode + ' RESPONSE ' + JSON.serialize(resp).left(1500));
    System.debug(LoggingLevel.ERROR, mode + ' lines ' + [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :qt.Id] + ', relationships ' +
        [SELECT COUNT() FROM QuoteLineRelationship WHERE QuoteId = :qt.Id]);
    Database.rollback(sp);
}
