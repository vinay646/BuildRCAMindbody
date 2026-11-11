// Phase 0 – org readiness check. Read-only; run BEFORE the first deploy:
//   sf apex run --target-org mindbody-dev --file scripts/apex/00_org_readiness.apex
// Every line in the debug log starting with READY / MISSING tells you what to turn on in Setup.

Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
List<String> out = new List<String>();
Integer missing = 0;

// [object, what turns it on]
List<List<String>> objects = new List<List<String>>{
    new List<String>{ 'ProductCatalog', 'Revenue Cloud: Product Catalog Management (PD-01)' },
    new List<String>{ 'ProductCategory', 'Product Catalog Management (PD-01)' },
    new List<String>{ 'ProductSellingModel', 'Revenue Cloud: Subscription Management / selling models (PD-09)' },
    new List<String>{ 'ProductSellingModelOption', 'Selling models (PD-09)' },
    new List<String>{ 'ProrationPolicy', 'Selling models – proration (BIL-04)' },
    new List<String>{ 'ProductRelatedComponent', 'Product Catalog Management – bundles (PD-02)' },
    new List<String>{ 'ProductComponentGroup', 'Product Catalog Management – bundles (PD-02)' },
    new List<String>{ 'ProductRelationshipType', 'Product Catalog Management – bundles (PD-02)' },
    new List<String>{ 'AttributeDefinition', 'Product Catalog Management – attributes (PD-07)' },
    new List<String>{ 'AttributePicklist', 'Product Catalog Management – attributes (PD-07)' },
    new List<String>{ 'ProductAttributeDefinition', 'Product Catalog Management – attributes (PD-07)' },
    new List<String>{ 'ExpressionSet', 'Revenue Cloud: Salesforce Pricing – pricing procedures (phase 3)' },
    new List<String>{ 'QuoteLineGroup', 'Revenue Cloud: Transaction Management – quote line groups (phase 5)' },
    new List<String>{ 'ContactPointAddress', 'Contact Point Address (US-03)' },
    new List<String>{ 'BillingSchedule', 'Revenue Cloud Billing (phase 7)' },
    new List<String>{ 'Invoice', 'Revenue Cloud Billing (phase 7)' },
    new List<String>{ 'RateCard', 'Revenue Cloud: Rate Management – usage rate cards (PD-05, phase 7)' },
    new List<String>{ 'UsageResource', 'Revenue Cloud: Usage Management (phase 7)' }
};
for (List<String> o : objects) {
    Boolean ok = gd.containsKey(o[0].toLowerCase());
    if (!ok) missing++;
    out.add((ok ? 'READY   ' : 'MISSING ') + o[0] + ' – ' + o[1]);
}

// Asset live quantity used by the location count (RLP-01)
Boolean assetQty = Schema.SObjectType.Asset.fields.getMap().containsKey('currentquantity');
out.add((assetQty ? 'READY   ' : 'CHECK   ') + 'Asset.CurrentQuantity – ARM asset lifecycle (falls back to Asset.Quantity)');

// Multi-currency with the four selling currencies (PRC-01)
Set<String> need = new Set<String>{ 'USD', 'GBP', 'AUD', 'EUR' };
if (gd.containsKey('currencytype')) {
    Set<String> active = new Set<String>();
    for (SObject c : Database.query('SELECT IsoCode FROM CurrencyType WHERE IsActive = true')) {
        active.add((String) c.get('IsoCode'));
    }
    Set<String> gap = need.clone();
    gap.removeAll(active);
    if (!gap.isEmpty()) missing++;
    out.add((gap.isEmpty() ? 'READY   ' : 'MISSING ') + 'Active currencies ' + active
        + (gap.isEmpty() ? '' : ' – add ' + gap + ' in Setup > Company Information > Currencies'));
} else {
    missing++;
    out.add('MISSING Multi-currency – Setup > Company Information > enable multiple currencies, then add USD, GBP, AUD, EUR (PRC-01)');
}

// State and country picklists (demo addresses use full names)
Boolean scp = Schema.SObjectType.Account.fields.getMap().containsKey('billingcountrycode');
out.add((scp ? 'READY   ' : 'CHECK   ') + 'State and country picklists – recommended for tax (BIL-12) and ERP address sync');

// Standard price book
List<Pricebook2> std = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
out.add((!std.isEmpty() && std[0].IsActive ? 'READY   ' : 'CHECK   ')
    + 'Standard Price Book active (the pricebooks step activates it if needed)');

// Sandbox?
Organization org = [SELECT Name, IsSandbox, OrganizationType FROM Organization LIMIT 1];
out.add('INFO    Org ' + org.Name + ' (' + org.OrganizationType + (org.IsSandbox ? ', sandbox' : ', NOT a sandbox') + ')');

// Already deployed?
out.add((Schema.SObjectType.Account.fields.getMap().containsKey('payer_type__c') ? 'INFO    ' : 'INFO    not ')
    + 'deployed yet: phase 1 fields (Account.Payer_Type__c)');

System.debug(LoggingLevel.ERROR, '==== Mindbody ARM org readiness: ' + missing + ' item(s) missing ====');
for (String l : out) System.debug(LoggingLevel.ERROR, l);
