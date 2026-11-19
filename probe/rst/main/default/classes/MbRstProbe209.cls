public class MbRstProbe209 {
    // execute(g, o, p, c, x, t)
    public static Object run() {
        RevSalesTrxn.GraphRequest g = null; RevSalesTrxn.PricingPreferenceEnum p = RevSalesTrxn.PricingPreferenceEnum.Force; RevSalesTrxn.CatalogRatesPreferenceEnum c = RevSalesTrxn.CatalogRatesPreferenceEnum.Skip; RevSalesTrxn.ConfigurationOptionsInput o = new RevSalesTrxn.ConfigurationOptionsInput(); RevSalesTrxn.TaxPreferenceEnum t = RevSalesTrxn.TaxPreferenceEnum.Skip; RevSalesTrxn.ConfigurationExecutionEnum x = RevSalesTrxn.ConfigurationExecutionEnum.Skip;
        return RevSalesTrxn.PlaceSalesTransactionExecutor.execute(g, o, p, c, x, t);
    }
}
