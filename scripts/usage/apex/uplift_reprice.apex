// CHANGES test renewal quote 00000316 only: 5% uplift on its lines, reprice, show prices
Quote q = [SELECT Id FROM Quote WHERE QuoteNumber = '00000316'];
List<QuoteLineItem> ls = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id];
for (QuoteLineItem l : ls) l.UnitPriceUplift = 5;
update ls;
RepriceQuotesPST.reprice(new Set<String>{ q.Id });
for (QuoteLineItem l : [SELECT Product2.ProductCode, Quantity, ListPrice, UnitPrice, NetUnitPrice, UnitPriceUplift, ApplUnitPriceUpliftPct FROM QuoteLineItem WHERE QuoteId = :q.Id AND Product2.ProductCode = 'MB-ULT'])
    System.debug(LoggingLevel.ERROR, 'ULT qty ' + l.Quantity + ' list ' + l.ListPrice + ' unit ' + l.UnitPrice + ' net ' + l.NetUnitPrice + ' uplift ' + l.UnitPriceUplift + ' applied ' + l.ApplUnitPriceUpliftPct);
