// CHANGES the org: creates Price Revision Policy "Mindbody renewal uplift" (Flat) if missing, sets it + 5% uplift on the latest test renewal quote (MR103 Q2C04 account), reprices with 0% and 5%
List<PriceRevisionPolicy> ps = [SELECT Id FROM PriceRevisionPolicy WHERE Name = 'Mindbody renewal uplift' LIMIT 1];
PriceRevisionPolicy p;
if (ps.isEmpty()) { p = new PriceRevisionPolicy(Name = 'Mindbody renewal uplift', PolicyType = 'Flat', EffectiveFrom = Date.newInstance(2026, 1, 1)); insert p; } else p = ps[0];
Quote q = [SELECT Id, QuoteNumber FROM Quote WHERE OriginalActionType = 'Renew' AND Opportunity.Account.Name LIKE 'MR103 Q2C04%' ORDER BY CreatedDate DESC LIMIT 1];
List<QuoteLineItem> ls = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id];
for (Decimal u : new List<Decimal>{ 0, 5 }) {
    for (QuoteLineItem l : ls) { l.PriceRevisionPolicyId = p.Id; l.UnitPriceUplift = u; }
    update ls;
    RepriceQuotesPST.reprice(new Set<String>{ q.Id });
    QuoteLineItem r = [SELECT NetUnitPrice, ApplUnitPriceUpliftPct FROM QuoteLineItem WHERE QuoteId = :q.Id AND Product2.ProductCode = 'MB-ULT' LIMIT 1];
    System.debug(LoggingLevel.ERROR, q.QuoteNumber + ' uplift ' + u + '% -> net ' + r.NetUnitPrice + ' applied ' + r.ApplUnitPriceUpliftPct);
}
