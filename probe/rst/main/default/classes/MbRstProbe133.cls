public class MbRstProbe133 {
    // execute(g, p, c, x, o, t)
    public static Object run() {
        RevSalesTrxn.GraphRequest g = null; RevSalesTrxn.PricingPreferenceEnum p = RevSalesTrxn.PricingPreferenceEnum.Force; RevSalesTrxn.CatalogRatesPreferenceEnum c = RevSalesTrxn.CatalogRatesPreferenceEnum.Skip; RevSalesTrxn.ConfigurationOptionsInput o = new RevSalesTrxn.ConfigurationOptionsInput(); RevSalesTrxn.TaxPreferenceEnum t = RevSalesTrxn.TaxPreferenceEnum.Skip; RevSalesTrxn.ConfigurationExecutionEnum x = RevSalesTrxn.ConfigurationExecutionEnum.Skip;
        return new RevSalesTrxn.PlaceSalesTransactionExecutor().execute(g, p, c, x, o, t);
    }
}
