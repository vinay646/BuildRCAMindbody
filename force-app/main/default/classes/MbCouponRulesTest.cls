@IsTest
private class MbCouponRulesTest {
    static Id quoteFor(Account a, String prior, Integer term, List<String> productCodes) {
        Opportunity o = new Opportunity(Name = 'T', AccountId = a.Id, StageName = 'Prospecting', CloseDate = Date.today(),
                                        MB_Prior_System__c = prior);
        insert o;
        Quote q = new Quote(Name = 'T', OpportunityId = o.Id, Pricebook2Id = Test.getStandardPricebookId());
        q.put('RLM_TermMonths__c', term);
        insert q;
        List<QuoteLineItem> lines = new List<QuoteLineItem>();
        for (String code : productCodes) {
            Product2 p = new Product2(Name = code, ProductCode = code, IsActive = true, Family = 'Recurring');
            insert p;
            PricebookEntry e = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = p.Id, UnitPrice = 10, IsActive = true);
            insert e;
            lines.add(new QuoteLineItem(QuoteId = q.Id, Product2Id = p.Id, PricebookEntryId = e.Id, Quantity = 1, UnitPrice = 10));
        }
        insert lines;
        return q.Id;
    }

    static String run(Id quoteId, String code) {
        MbCouponRules.Request r = new MbCouponRules.Request();
        r.quoteId = quoteId;
        r.couponCode = code;
        return MbCouponRules.check(new List<MbCouponRules.Request>{ r })[0].message;
    }

    @IsTest
    static void rules() {
        Account newLogo = new Account(Name = 'New logo');
        insert newLogo;
        Id ok = quoteFor(newLogo, 'Vagaro', 24, new List<String>{ 'MB-STR', 'MB-PAY' });
        System.assertEquals(null, run(ok, 'launch3'));
        System.assertNotEquals(null, run(ok, 'GROW2'));
        Id sw = quoteFor(newLogo, 'Vagaro', 24, new List<String>{ 'MB-ULT', 'MB-DCV' });
        System.assertEquals(null, run(sw, 'SWITCH50'));
        System.assertEquals(null, run(ok, 'OTHER'));
        System.assertEquals(null, run(ok, ''));

        Id bad = quoteFor(newLogo, 'None', 12, new List<String>{ 'MB-ACC' });
        System.assert(run(bad, 'LAUNCH3').contains('Starter'));
        String s = run(bad, 'SWITCH50');
        System.assert(s.contains('Prior System') && s.contains('24 months') && s.contains('Data Conversion'), s);

        Account existing = new Account(Name = 'Existing');
        insert existing;
        insert new Asset(Name = 'Plan', AccountId = existing.Id);
        System.assert(MbCouponRules.isExistingCustomer(existing.Id));
        System.assert(!MbCouponRules.isExistingCustomer(null));
    }
}
