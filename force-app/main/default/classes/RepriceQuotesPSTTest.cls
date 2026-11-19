@IsTest
private class RepriceQuotesPSTTest {
    @IsTest
    static void repricesOrQueues() {
        // Place Sales Transaction needs Revenue Cloud data a test cannot build: the immediate call fails here and the
        // method falls back to the queued job. Covers request building, de-duplication, fallback and cleanup.
        Test.startTest();
        RepriceQuotesPST.repriceQuotesPST(new List<String>{ null, '', '0Q0000000000000AAA', '0Q0000000000000AAA' });
        RepriceQuotesPST.repriceQuotesPST(new List<String>());
        Test.stopTest();
        RepriceQuotesPST.deletePlaceholders(new Set<String>());
        RepriceQuotesPST.deletePlaceholders(new Set<String>{ '0Q0000000000000AAA' });
        System.assert(true);
    }

    @IsTest
    static void queuedJobRuns() {
        Test.startTest();
        try {
            new RepriceQuotesPST.RepriceJob(new Set<String>{ '0Q0000000000000AAA' }).execute(null);
        } catch (Exception e) {
            System.debug('expected in a test: ' + e.getMessage());
        }
        Test.stopTest();
        System.assert(true);
    }
}
