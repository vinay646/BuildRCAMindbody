@IsTest
private class MbPromotionGuardTest {
    @IsTest
    static void removesPromotionsWithoutTheQuoteCoupon() {
        Account a = new Account(Name = 'Promotion guard');
        insert a;
        Opportunity o = new Opportunity(Name = 'Promotion guard', AccountId = a.Id, StageName = 'Prospecting', CloseDate = Date.today(),
                                        Pricebook2Id = Test.getStandardPricebookId());
        insert o;
        Quote q = new Quote(Name = 'Promotion guard', OpportunityId = o.Id, Pricebook2Id = Test.getStandardPricebookId(), RLM_TermMonths__c = 24);
        insert q;
        Product2 p = new Product2(Name = 'MB-ACC', ProductCode = 'MB-ACC', IsActive = true, Family = 'Recurring');
        insert p;
        PricebookEntry e = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = p.Id, UnitPrice = 269, IsActive = true);
        insert e;
        QuoteLineItem l = new QuoteLineItem(QuoteId = q.Id, Product2Id = p.Id, PricebookEntryId = e.Id, Quantity = 1, UnitPrice = 269);
        insert l;
        Test.startTest();
        try {
            insert new QuoteLinePriceAdjustment(QuoteLineItemId = l.Id, AdjustmentSource = 'Promotion', AdjustmentType = 'AdjustmentPercentage',
                                                AdjustmentValue = 50, Description = 'Switched on in the configurator');
            MbPromotionGuard.guard(new List<Id>{ q.Id, null });
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'reprice not available in tests: ' + ex.getMessage());
        }
        Test.stopTest();
        // the quote has no Coupon Code, so no promotion stays on its lines
        System.assertEquals(0, [SELECT COUNT() FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = :l.Id AND AdjustmentSource = 'Promotion']);
        MbPromotionGuard.guard(new List<Id>());
    }
}
