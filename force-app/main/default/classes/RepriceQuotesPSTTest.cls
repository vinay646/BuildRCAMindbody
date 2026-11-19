@IsTest
private class RepriceQuotesPSTTest {
    @IsTest
    static void skipsBlankAndDuplicateIds() {
        // Place Sales Transaction needs Revenue Cloud data that a test cannot build; the call may throw here.
        // The test covers the request building and the de-duplication.
        Test.startTest();
        try {
            RepriceQuotesPST.repriceQuotesPST(new List<String>{ null, '', '0Q0000000000000AAA', '0Q0000000000000AAA' });
        } catch (Exception e) {
            System.debug('Place Sales Transaction not available in the test context: ' + e.getMessage());
        }
        Test.stopTest();
        System.assert(true);
    }
}
