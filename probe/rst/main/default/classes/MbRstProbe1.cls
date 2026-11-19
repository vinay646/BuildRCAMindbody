public class MbRstProbe1 {
    // execute(g, p, x, o)
    public static Object run() {
        RevSalesTrxn.GraphRequest g = null; RevSalesTrxn.PricingPreferenceEnum p = RevSalesTrxn.PricingPreferenceEnum.Force; RevSalesTrxn.CatalogRatesPreferenceEnum c = RevSalesTrxn.CatalogRatesPreferenceEnum.Skip; RevSalesTrxn.ConfigurationOptionsInput o = new RevSalesTrxn.ConfigurationOptionsInput(); RevSalesTrxn.TaxPreferenceEnum t = RevSalesTrxn.TaxPreferenceEnum.Skip; RevSalesTrxn.ConfigurationExecutionEnum x = RevSalesTrxn.ConfigurationExecutionEnum.values()[0];
        return RevSalesTrxn.PlaceSalesTransactionExecutor.execute(g, p, x, o);
    }
}
