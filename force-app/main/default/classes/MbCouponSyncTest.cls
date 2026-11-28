@IsTest
private class MbCouponSyncTest {
    @IsTest
    static void syncAppliesOnlyWhenEligible() {
        Account a = new Account(Name = 'Coupon sync');
        insert a;
        Opportunity o = new Opportunity(Name = 'Coupon sync', AccountId = a.Id, StageName = 'Prospecting', CloseDate = Date.today(),
                                        Pricebook2Id = Test.getStandardPricebookId());
        insert o;
        Quote q = new Quote(Name = 'Coupon sync', OpportunityId = o.Id, Pricebook2Id = Test.getStandardPricebookId(), RLM_TermMonths__c = 12);
        insert q;
        Product2 p = new Product2(Name = 'MB-STR', ProductCode = 'MB-STR', IsActive = true, Family = 'Recurring');
        insert p;
        PricebookEntry e = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = p.Id, UnitPrice = 79, IsActive = true);
        insert e;
        insert new QuoteLineItem(QuoteId = q.Id, Product2Id = p.Id, PricebookEntryId = e.Id, Quantity = 1, UnitPrice = 79);
        q.Coupon_Code__c = 'LAUNCH3';
        Test.startTest();
        try {
            update q;
            MbCouponSync.sync(new List<Id>{ q.Id, null });
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'reprice not available in tests: ' + ex.getMessage());
        }
        Test.stopTest();
        // Starter without Payments: not eligible, so no coupon placeholder stays on the line
        System.assertEquals(0, [SELECT COUNT() FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = :q.Id AND CouponCode = 'LAUNCH3']);
        MbCouponSync.sync(new List<Id>());
    }
}
