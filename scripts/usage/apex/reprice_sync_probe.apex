// Does PlaceSalesTransactionExecutor.execute price synchronously? Quote 00000152 (COUPON-FLOW add line later, coupon NEWPROMO5):
// add a placeholder to its Accelerate line, execute, and read the adjustments in the same transaction. Rolled back at the end.
Savepoint sp = Database.setSavepoint();
QuoteLineItem l = [SELECT Id, QuoteId, NetUnitPrice FROM QuoteLineItem WHERE Quote.QuoteNumber = '00000152' AND Product2.ProductCode = 'MB-ACC' LIMIT 1];
insert new QuoteLinePriceAdjustment(QuoteLineItemId = l.Id, AdjustmentSource = 'Promotion', AdjustmentType = 'AdjustmentPercentage',
    AdjustmentValue = 0, CouponCode = 'NEWPROMO5', Description = 'Quote coupon code');
RevSalesTrxn.ConfigurationOptionsInput config = new RevSalesTrxn.ConfigurationOptionsInput();
RevSalesTrxn.RecordResource rec = new RevSalesTrxn.RecordResource(Quote.getSObjectType(), 'PATCH', l.QuoteId);
RevSalesTrxn.GraphRequest graph = new RevSalesTrxn.GraphRequest('g', new List<RevSalesTrxn.RecordWithReferenceRequest>{ new RevSalesTrxn.RecordWithReferenceRequest('refQuote', rec) });
Object resp = RevSalesTrxn.PlaceSalesTransactionExecutor.execute(graph, RevSalesTrxn.PricingPreferenceEnum.FORCE, RevSalesTrxn.ConfigurationExecutionEnum.SYSTEM, config, null);
System.debug(LoggingLevel.ERROR, 'RESPONSE ' + JSON.serialize(resp).left(800));
QuoteLineItem after = [SELECT NetUnitPrice FROM QuoteLineItem WHERE Id = :l.Id];
System.debug(LoggingLevel.ERROR, 'SAME TRANSACTION: net ' + l.NetUnitPrice + ' -> ' + after.NetUnitPrice + ' | adjustments ' +
    [SELECT AdjustmentValue, CouponCode, PriceAdjustmentCauseId, Description FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = :l.Id]);
Database.rollback(sp);
System.debug(LoggingLevel.ERROR, 'ROLLED BACK');
