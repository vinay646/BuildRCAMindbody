// CHANGES test data in dev: quote 00000398 (coupon LAUNCH3). Simulates GROW2 switched on and replacing the coupon: deletes the LAUNCH3 discount, adds a 100% promotion; runs MbPromotionGuard; LAUNCH3 should come back ($39)
Quote q = [SELECT Id FROM Quote WHERE QuoteNumber = '00000398'];
QuoteLineItem l = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id AND Product2.ProductCode = 'MB-STR'];
delete [SELECT Id FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = :q.Id AND AdjustmentSource = 'Promotion'];
insert new QuoteLinePriceAdjustment(QuoteLineItemId = l.Id, AdjustmentSource = 'Promotion', AdjustmentType = 'AdjustmentPercentage', AdjustmentValue = 100, Description = 'GROW2 toggle test');
MbPromotionGuard.guard(new List<Id>{ q.Id });
String after = '';
for (QuoteLinePriceAdjustment a : [SELECT AdjustmentValue, CouponCode FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = :l.Id AND AdjustmentSource = 'Promotion']) after += a.AdjustmentValue + '/' + a.CouponCode + ' ';
System.debug(LoggingLevel.ERROR, 'REPLACE after [' + after + '] starter net ' + [SELECT NetUnitPrice FROM QuoteLineItem WHERE Id = :l.Id].NetUnitPrice);
