// READ ONLY: RevSalesTrxn types and visibility of the executor.
for (String n : new List<String>{ 'RecordResource', 'PlaceSalesTransactionRequest', 'ConfigurationPreferenceInput', 'ConfigurationMethodEnum',
    'ConfigurationPreference', 'ConfigurationPreferenceEnum', 'ConfigurationOptions', 'PlaceSalesTransactionInput', 'SalesTransactionContext',
    'GraphRequest', 'RecordWithReferenceRequest', 'PricingPreferenceEnum', 'TaxPreferenceEnum', 'CatalogRatesPreferenceEnum',
    'ConfigurationOptionsInput', 'PlaceSalesTransactionResponse', 'ErrorResponse' }) {
    System.debug(LoggingLevel.ERROR, 'TYPE RevSalesTrxn.' + n + ' -> ' + (Type.forName('RevSalesTrxn', n) != null));
}
RevSalesTrxn.PlaceSalesTransactionExecutor visible = null;
System.debug(LoggingLevel.ERROR, 'EXECUTOR declared ok');
