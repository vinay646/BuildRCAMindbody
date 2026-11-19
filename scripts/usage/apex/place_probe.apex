// READ ONLY: which Apex place / pricing classes exist in this org.
for (String n : new List<String>{
    'PlaceQuote.PlaceQuoteExecutor', 'PlaceQuote.GraphRequest', 'PlaceQuote.RecordWithReferenceRequest', 'PlaceQuote.RecordResource',
    'PlaceQuote.PricingPreferenceEnum', 'PlaceQuote.ConfigurationInputEnum', 'PlaceQuote.ConfigurationOptionsInput', 'PlaceQuote.PlaceQuoteResponse',
    'RevSalesTrxn.PlaceSalesTransactionExecutor', 'RevSalesTrxn.GraphRequest', 'RevSalesTrxn.RecordWithReferenceRequest',
    'RevSalesTrxn.PricingPreferenceEnum', 'RevSalesTrxn.PlaceSalesTransactionResponse', 'RevSalesTrxn.ConfigurationOptionsInput',
    'RevSalesTrxn.ConfigurationInputEnum', 'RevSalesTrxn.CatalogRatesPreferenceEnum', 'RevSalesTrxn.TaxPreferenceEnum' }) {
    List<String> p = n.split('\\.');
    System.debug('TYPE ' + n + ' -> ' + (Type.forName(p[0], p[1]) != null));
}
