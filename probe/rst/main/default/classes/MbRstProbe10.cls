public class MbRstProbe10 {
    // execute(g, p, ci, o, c, t)
    public static Object run() {
        RevSalesTrxn.GraphRequest g = null; RevSalesTrxn.PricingPreferenceEnum p = RevSalesTrxn.PricingPreferenceEnum.Force; RevSalesTrxn.CatalogRatesPreferenceEnum c = RevSalesTrxn.CatalogRatesPreferenceEnum.Skip; RevSalesTrxn.ConfigurationOptionsInput o = new RevSalesTrxn.ConfigurationOptionsInput(); RevSalesTrxn.TaxPreferenceEnum t = RevSalesTrxn.TaxPreferenceEnum.Skip; PlaceQuote.ConfigurationInputEnum ci = PlaceQuote.ConfigurationInputEnum.Skip;
        return RevSalesTrxn.PlaceSalesTransactionExecutor.execute(g, p, ci, o, c, t);
    }
}
