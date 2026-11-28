// CHANGES test data in dev: adds a 50% promotion adjustment (as if switched on in the configurator) to the Starter line of quotes 00000398 (LAUNCH3) and 00000397 (no coupon), then runs MbPromotionGuard
List<Id> qids = new List<Id>();
for (QuoteLineItem l : [SELECT Id, QuoteId, Quote.QuoteNumber FROM QuoteLineItem WHERE Quote.QuoteNumber IN ('00000398','00000397') AND Product2.ProductCode = 'MB-STR']) {
    insert new QuoteLinePriceAdjustment(QuoteLineItemId = l.Id, AdjustmentSource = 'Promotion', AdjustmentType = 'AdjustmentPercentage', AdjustmentValue = 50, Description = 'Configurator toggle test');
    qids.add(l.QuoteId);
}
String before = '';
for (QuoteLinePriceAdjustment a : [SELECT QuoteLineItem.Quote.QuoteNumber, AdjustmentValue, CouponCode FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId IN :qids AND AdjustmentSource = 'Promotion']) before += a.QuoteLineItem.Quote.QuoteNumber + ':' + a.AdjustmentValue + '/' + a.CouponCode + ' ';
MbPromotionGuard.guard(qids);
String after = '';
for (QuoteLinePriceAdjustment a : [SELECT QuoteLineItem.Quote.QuoteNumber, AdjustmentValue, CouponCode FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId IN :qids AND AdjustmentSource = 'Promotion']) after += a.QuoteLineItem.Quote.QuoteNumber + ':' + a.AdjustmentValue + '/' + a.CouponCode + ' ';
String prices = '';
for (QuoteLineItem l : [SELECT Quote.QuoteNumber, NetUnitPrice FROM QuoteLineItem WHERE QuoteId IN :qids AND Product2.ProductCode = 'MB-STR']) prices += l.Quote.QuoteNumber + ':' + l.NetUnitPrice + ' ';
System.debug(LoggingLevel.ERROR, 'GUARD before [' + before + '] after [' + after + '] starter prices [' + prices + ']');
