// CHANGES QA quote 00000288: re-applies its Coupon Code (MbCouponSync: coupon on every line if the quote qualifies, other promotions removed, reprice) and reports the result
Quote q = [SELECT Id, Coupon_Code__c, RLM_TermMonths__c, Prior_system__c, Opportunity.Prior_System__c FROM Quote WHERE QuoteNumber = '00000288'];
String why = MbCouponRules.check(q.Id, q.Coupon_Code__c);
String lines = '';
for (QuoteLineItem l : [SELECT Product2.ProductCode, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = :q.Id AND ListPrice > 0]) lines += l.Product2.ProductCode + ':' + l.NetUnitPrice + ' ';
System.debug(LoggingLevel.ERROR, 'BEFORE code=' + q.Coupon_Code__c + ' term=' + q.RLM_TermMonths__c + ' prior=' + q.Opportunity.Prior_System__c + '/' + q.Prior_system__c + ' eligible=' + (why == null) + ' reason=' + why + ' lines=' + lines);
MbCouponSync.sync(new List<Id>{ q.Id });
String after = '';
for (QuoteLineItem l : [SELECT Product2.ProductCode, NetUnitPrice, TotalPrice, MB_Promotion_Applied__c FROM QuoteLineItem WHERE QuoteId = :q.Id AND ListPrice > 0]) after += l.Product2.ProductCode + ':' + l.NetUnitPrice + '/total ' + l.TotalPrice + '/promo ' + l.MB_Promotion_Applied__c + ' ';
String adj = '';
for (QuoteLinePriceAdjustment a : [SELECT QuoteLineItem.Product2.ProductCode, AdjustmentValue, CouponCode FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = :q.Id AND AdjustmentSource = 'Promotion']) adj += a.QuoteLineItem.Product2.ProductCode + ':' + a.AdjustmentValue + '/' + a.CouponCode + ' ';
System.debug(LoggingLevel.ERROR, 'AFTER lines=' + after + ' promotions=' + adj);
