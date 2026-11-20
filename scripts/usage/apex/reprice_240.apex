// CHANGES test quote 00000240 only: reprice it (pricing Force) to see whether its manual discount survives
Quote q = [SELECT Id FROM Quote WHERE QuoteNumber = '00000240'];
QuoteLineItem before = [SELECT NetUnitPrice, Discount, DiscountAmount FROM QuoteLineItem WHERE QuoteId = :q.Id AND Product2.ProductCode = 'MB-ACC'];
System.debug('BEFORE ' + JSON.serialize(before));
RepriceQuotesPST.reprice(new Set<String>{ q.Id });
QuoteLineItem after = [SELECT NetUnitPrice, Discount, DiscountAmount FROM QuoteLineItem WHERE QuoteId = :q.Id AND Product2.ProductCode = 'MB-ACC'];
System.debug('AFTER ' + JSON.serialize(after));
for (QuoteLinePriceAdjustment a : [SELECT AdjustmentSource, AdjustmentType, AdjustmentValue, AppliedAdjustmentAmount FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = :q.Id]) System.debug('ADJ240 ' + JSON.serialize(a));
for (QuoteLinePriceAdjustment a : [SELECT AdjustmentSource, AdjustmentType, AdjustmentValue, AppliedAdjustmentAmount, CreatedDate FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.Quote.QuoteNumber = '00000252']) System.debug('ADJ252 ' + JSON.serialize(a));
