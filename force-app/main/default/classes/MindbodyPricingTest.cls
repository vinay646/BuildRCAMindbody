/** Tests the pricing waterfall against the spec's numbers (12.2) using the deployed custom metadata. */
@IsTest
private class MindbodyPricingTest {

    static MindbodyPricing.PriceRequest req(String code, Decimal listPrice, Integer hierarchy, Integer added,
                                            Integer term, String freq) {
        MindbodyPricing.PriceRequest r = new MindbodyPricing.PriceRequest();
        r.productCode = code;
        r.listPrice = listPrice;
        r.hierarchyLocations = hierarchy;
        r.newLocations = added;
        r.termMonths = term;
        r.billingFrequency = freq;
        return r;
    }

    /** Compares numbers by value, so 449.1 equals 449.10 and 10 equals 10.00. */
    static void eq(Decimal expected, Decimal actual) {
        eq(expected, actual, '');
    }

    static void eq(Decimal expected, Decimal actual, String message) {
        Assert.isTrue(expected == actual, 'expected ' + expected + ', got ' + actual + (String.isBlank(message) ? '' : ' – ' + message));
    }

    @IsTest
    static void pulseWorkedExample() {
        // spec 12.2: Pulse adds 2 Ultimate locations, 12 already active, 36 months, annual prepay
        MindbodyPricing.PriceResult r = MindbodyPricing.price(req('MB-ULT', 499, 12, 2, 36, 'Annual'));
        eq(14, r.volumeLocations);
        eq(10, r.volumeDiscountPercent);
        eq(449.10, r.afterVolume);
        eq(404.19, r.afterTerm);
        eq(371.85, r.afterFrequency);
        eq(371.85, r.netPrice);
        eq(25.48, r.combinedDiscountPercent, 'spec rounds this to 25.5%');
        Assert.isFalse(r.belowFloor, 'above the $339 Ultimate floor');
        Assert.isTrue(r.needsApproval, '25.5% is above the 25% auto-approve limit');
        Assert.isTrue(r.approvalReasons[0].contains('sales manager'));
        // annual invoice for the 2 locations
        eq(8924.40, r.netPrice * 2 * 12);
    }

    @IsTest
    static void singleStudioNoDiscount() {
        MindbodyPricing.PriceResult r = MindbodyPricing.price(req('MB-STR', 79, 0, 1, null, 'Monthly'));
        eq(79, r.netPrice);
        eq(0, r.combinedDiscountPercent);
        Assert.isFalse(r.needsApproval);
    }

    @IsTest
    static void volumeBands() {
        Map<Integer, Decimal> expected = new Map<Integer, Decimal>{
            1 => 0, 3 => 0, 4 => 5, 10 => 5, 11 => 10, 50 => 10, 51 => 15, 200 => 15, 201 => 20, 1000 => 20 };
        for (Integer n : expected.keySet()) {
            eq(expected.get(n), MindbodyPricing.volumeDiscount(n), n + ' locations');
        }
    }

    @IsTest
    static void termAndFrequencyTables() {
        eq(0, MindbodyPricing.termDiscount(null));
        eq(0, MindbodyPricing.termDiscount(12));
        eq(5, MindbodyPricing.termDiscount(24));
        eq(10, MindbodyPricing.termDiscount(36));
        eq(0, MindbodyPricing.frequencyDiscount('Monthly'));
        eq(2, MindbodyPricing.frequencyDiscount('Quarterly'));
        eq(4, MindbodyPricing.frequencyDiscount('Semiannual'));
        eq(8, MindbodyPricing.frequencyDiscount('annual'));
    }

    @IsTest
    static void launch3AppliesWithPayments() {
        MindbodyPricing.PriceRequest q = req('MB-STR', 79, 0, 1, 12, 'Monthly');
        q.promoCode = 'launch3';
        q.paymentsOptedIn = true;
        MindbodyPricing.PriceResult r = MindbodyPricing.price(q);
        Assert.isTrue(r.promoApplied, String.join(r.messages, ' '));
        eq(39, r.promoPrice);
        eq(3, r.promoMonths);
        eq(79, r.netPrice, 'standard price after the promo months');
        Assert.isFalse(r.needsApproval, 'floor checks the standard price, not the promo price');
    }

    @IsTest
    static void launch3BlockedWithoutPayments() {
        MindbodyPricing.PriceRequest q = req('MB-STR', 79, 0, 1, 12, 'Monthly');
        q.promoCode = 'LAUNCH3';
        MindbodyPricing.PriceResult r = MindbodyPricing.price(q);
        Assert.isFalse(r.promoApplied);
        Assert.isTrue(String.join(r.messages, ' ').contains('Mindbody Payments'));
    }

    @IsTest
    static void switch50NeedsCompetitorConversionAndTerm() {
        MindbodyPricing.PriceRequest q = req('MB-ULT', 499, 0, 1, 12, 'Monthly');
        q.promoCode = 'SWITCH50';
        eq(3, MindbodyPricing.promoProblems(q, 'SWITCH50').size(), 'term, competitor and data conversion');
        q.termMonths = 24;
        q.priorSystemIsCompetitor = true;
        q.dataConversionOnQuote = true;
        MindbodyPricing.PriceResult r = MindbodyPricing.price(q);
        Assert.isTrue(r.promoApplied, String.join(r.messages, ' '));
        eq(474.05, r.netPrice, '499 less 5% for 24 months');
        eq(237.03, r.promoPrice, '50% off for 6 months');
        eq(6, r.promoMonths);
    }

    @IsTest
    static void manualDiscountBelowFloorNeedsVp() {
        MindbodyPricing.PriceRequest q = req('MB-STR', 79, 0, 1, null, 'Monthly');
        q.manualDiscountPercent = 30;
        MindbodyPricing.PriceResult r = MindbodyPricing.price(q);
        eq(55.30, r.netPrice);
        Assert.isTrue(r.belowFloor, 'below the $59 Starter floor');
        Assert.isTrue(r.approvalReasons[0].contains('VP Sales'));
    }

    @IsTest
    static void masterAgreementPriceSkipsDiscounts() {
        MindbodyPricing.PriceRequest q = req('MB-ENT', 0, 60, 0, 36, 'Annual');
        q.contractPrice = 300;
        MindbodyPricing.PriceResult r = MindbodyPricing.price(q);
        Assert.isTrue(r.contractPriceUsed);
        eq(300, r.netPrice, 'no volume, term or frequency discount on a contract price');
        Assert.isTrue(r.needsApproval, 'Enterprise always goes to the deal desk');
    }

    @IsTest
    static void unknownPromoIsReported() {
        MindbodyPricing.PriceRequest q = req('MB-ACC', 269, 0, 1, 12, 'Monthly');
        q.promoCode = 'NOPE';
        MindbodyPricing.PriceResult r = MindbodyPricing.price(q);
        Assert.isFalse(r.promoApplied);
        eq(269, r.netPrice);
    }
}
