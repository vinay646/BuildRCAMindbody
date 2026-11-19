public class MbRstProbeTypes {
    public static void run() {
        RevSalesTrxn.RecordResource r = new RevSalesTrxn.RecordResource(Quote.getSObjectType(), 'PATCH', null);
        r.fieldValues = new Map<String, Object>();
        RevSalesTrxn.RecordWithReferenceRequest w = new RevSalesTrxn.RecordWithReferenceRequest('q1', r);
        RevSalesTrxn.GraphRequest g = new RevSalesTrxn.GraphRequest('g', new List<RevSalesTrxn.RecordWithReferenceRequest>{ w });
    }
}
