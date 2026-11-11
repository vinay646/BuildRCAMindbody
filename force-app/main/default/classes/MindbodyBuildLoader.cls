/**
 * Loads the Mindbody ARM build data (static resource MB_Build_Data) into the org, one step at a time:
 *
 *   accounts    demo account hierarchy (spec 11.1, 7A) + Bill-To / Ship-To addresses      US-01..US-03
 *   catalog     catalog, 7 categories, selling models, proration policy                  PD-01, PD-09
 *   products    17 SKUs + feature components, category assignment, selling model options PD-01, PD-05, PD-06, PD-09
 *   bundles     tier bundles: component groups and components (tier matrix 3.1)          PD-02, PD-03, PD-04
 *   attributes  attribute picklists, definitions and product assignments (12.6)           PD-07, PD-02
 *   pricebooks  regional price books and entries per product x currency x selling model  PD-09, US-09
 *
 * Run from anonymous Apex:  MindbodyBuildLoader.run('catalog');
 * Every step is idempotent: records are matched on a natural key (name, product code, ...) and
 * updated, never duplicated. Fields that do not exist in this org's ARM release are skipped with a
 * warning instead of failing the step, and each failed record is reported with its error.
 */
public without sharing class MindbodyBuildLoader {

    public class LoaderException extends Exception {}

    public static final String RESOURCE = 'MB_Build_Data';
    public static final List<String> STEPS = new List<String>{ 'accounts', 'catalog', 'products', 'bundles', 'attributes', 'pricebooks' };

    public List<String> log = new List<String>();
    public Integer errors = 0;
    private Map<String, Object> data;
    private Set<String> warned = new Set<String>();

    // ================================================================== entry points

    public static MindbodyBuildLoader run(String step) {
        MindbodyBuildLoader l = new MindbodyBuildLoader(loadResource());
        l.runStep(step);
        l.printSummary(step);
        return l;
    }

    public MindbodyBuildLoader(Map<String, Object> data) {
        this.data = data;
    }

    public static Map<String, Object> loadResource() {
        List<StaticResource> sr = [SELECT Body FROM StaticResource WHERE Name = :RESOURCE LIMIT 1];
        if (sr.isEmpty()) {
            throw new LoaderException('Static resource ' + RESOURCE + ' is not deployed.');
        }
        return (Map<String, Object>) JSON.deserializeUntyped(sr[0].Body.toString());
    }

    public void runStep(String step) {
        switch on step {
            when 'accounts' { loadAccounts(); }
            when 'catalog' { loadCatalog(); }
            when 'products' { loadProducts(); }
            when 'bundles' { loadBundles(); }
            when 'attributes' { loadAttributes(); }
            when 'pricebooks' { loadPriceBooks(); }
            when else { throw new LoaderException('Unknown step "' + step + '". Steps: ' + String.join(STEPS, ', ')); }
        }
    }

    public void printSummary(String step) {
        System.debug(LoggingLevel.ERROR, '==== MindbodyBuildLoader step "' + step + '": ' + errors + ' error(s) ====');
        for (String line : log) {
            System.debug(LoggingLevel.ERROR, line);
        }
    }

    // ================================================================== steps

    /** Demo accounts, parents first, then a primary Bill-To for payers and a primary Ship-To for locations. */
    public void loadAccounts() {
        List<Object> accounts = listOf('accounts');
        Map<String, SObject> byName = new Map<String, SObject>();
        // load level by level so every parent exists before its children (spec 2.3)
        for (String level : new List<String>{ 'Corporate', 'Region', 'Franchisee', 'Location' }) {
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (Object o : accounts) {
                Map<String, Object> a = (Map<String, Object>) o;
                if ((String) a.get('level') != level) {
                    continue;
                }
                Map<String, Object> addr = (Map<String, Object>) a.get('address');
                Map<String, Object> r = new Map<String, Object>{
                    'Name' => a.get('name'),
                    'Account_Level__c' => level,
                    'Payer_Type__c' => a.get('payer'),
                    'CurrencyIsoCode' => a.get('currency'),
                    'Segment__c' => a.get('segment'),
                    'Vertical__c' => a.get('vertical')
                };
                if (a.get('parent') != null) {
                    SObject parent = byName.get((String) a.get('parent'));
                    if (parent == null) {
                        fail('Account ' + a.get('name') + ': parent ' + a.get('parent') + ' was not loaded');
                        continue;
                    }
                    r.put('ParentId', parent.Id);
                }
                if (addr != null) {
                    r.put('BillingStreet', addr.get('street'));
                    r.put('BillingCity', addr.get('city'));
                    r.put('BillingState', addr.get('state'));
                    r.put('BillingPostalCode', addr.get('postalCode'));
                    r.put('BillingCountry', addr.get('country'));
                }
                rows.add(r);
            }
            if (!rows.isEmpty()) {
                byName.putAll(sync('Account', new List<String>{ 'Name' }, rows, null, null,
                    new Set<String>{ 'CurrencyIsoCode' }));
            }
        }

        if (!hasObject('ContactPointAddress')) {
            warn('ContactPointAddress is not available – addresses skipped');
            return;
        }
        List<Map<String, Object>> addrRows = new List<Map<String, Object>>();
        for (Object o : accounts) {
            Map<String, Object> a = (Map<String, Object>) o;
            Map<String, Object> addr = (Map<String, Object>) a.get('address');
            SObject acc = byName.get((String) a.get('name'));
            if (addr == null || acc == null) {
                continue;
            }
            if ((String) a.get('payer') == 'Self-Pay') {
                addrRows.add(address(acc.Id, 'Billing', 'Primary Bill-To', addr));
            }
            if ((String) a.get('level') == 'Location' || a.get('parent') == null) {
                addrRows.add(address(acc.Id, 'Shipping', 'Primary Ship-To', addr));
            }
        }
        sync('ContactPointAddress', new List<String>{ 'ParentId', 'AddressType', 'Name' }, addrRows,
            'ParentId IN :ids', new Map<String, Object>{ 'ids' => idsOf(byName.values()) }, null);
        info('Billing accounts are created in the billing phase (US-25); not part of this step.');
    }

    /** Catalog, categories, selling models and the proration policy. */
    public void loadCatalog() {
        Map<String, Object> cat = (Map<String, Object>) data.get('catalog');
        Map<String, SObject> catalogs = sync('ProductCatalog', new List<String>{ 'Name' }, new List<Map<String, Object>>{
            new Map<String, Object>{ 'Name' => cat.get('name'), 'Code' => cat.get('code'),
                'Description' => cat.get('description'), 'CatalogType' => 'Sales',
                'EffectiveStartDate' => Datetime.newInstanceGmt(2026, 1, 1) }
        }, null, null, null);
        SObject catalog = catalogs.get(String.valueOf(cat.get('name')));
        if (catalog != null) {
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (Object o : listOf('categories')) {
                Map<String, Object> c = (Map<String, Object>) o;
                rows.add(new Map<String, Object>{ 'CatalogId' => catalog.Id, 'Name' => c.get('name'),
                    'Code' => c.get('code'), 'SortOrder' => c.get('sequence'), 'IsNavigational' => true });
            }
            sync('ProductCategory', new List<String>{ 'CatalogId', 'Name' }, rows,
                'CatalogId = :cid', new Map<String, Object>{ 'cid' => catalog.Id }, null);
        }

        List<Map<String, Object>> psm = new List<Map<String, Object>>();
        for (Object o : listOf('sellingModels')) {
            Map<String, Object> m = (Map<String, Object>) o;
            Map<String, Object> r = new Map<String, Object>{ 'Name' => m.get('name'),
                'SellingModelType' => m.get('type'), 'Status' => 'Active' };
            if (m.get('pricingTerm') != null) {
                r.put('PricingTerm', m.get('pricingTerm'));
                r.put('PricingTermUnit', m.get('pricingTermUnit'));
            }
            psm.add(r);
        }
        // selling models cannot change type once used: create only, never update
        sync('ProductSellingModel', new List<String>{ 'Name' }, psm, null, null, null, true);
        prorationPolicyId();
    }

    /** Products and feature components, category assignment and selling model options. */
    public void loadProducts() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Map<String, Object> p : allProducts()) {
            Boolean bundle = p.get('bundle') == true;
            Map<String, Object> r = new Map<String, Object>{
                'Name' => p.get('name'), 'ProductCode' => p.get('code'), 'Description' => p.get('description'),
                'IsActive' => true, 'Product_Type__c' => p.get('productType'),
                'Allowed_Billing_Frequencies__c' => p.get('billingFrequencies'),
                'Unit_Of_Sale__c' => p.get('unit'), 'Integration_Status__c' => 'New',
                'IsSoldOnlyWithOtherProds' => p.get('soldOnlyWithOthers') == true
            };
            if (bundle) {
                r.put('Type', 'Bundle');
                r.put('ConfigureDuringSale', p.get('configurable') == true ? 'Allowed' : 'NotAllowed');
            }
            rows.add(r);
        }
        // Integration_Status__c is set to New on create only – the ERP integration owns it afterwards
        Map<String, SObject> products = sync('Product2', new List<String>{ 'ProductCode' }, rows, null, null,
            new Set<String>{ 'Integration_Status__c', 'Type' });

        // category assignment (catalog step must have run)
        Map<String, SObject> cats = byKey('ProductCategory', 'Name', 'Catalog.Name = :n',
            new Map<String, Object>{ 'n' => ((Map<String, Object>) data.get('catalog')).get('name') });
        List<Map<String, Object>> pcp = new List<Map<String, Object>>();
        for (Map<String, Object> p : allProducts()) {
            if (p.get('category') == null) {
                continue;
            }
            SObject c = cats.get((String) p.get('category'));
            SObject prod = products.get((String) p.get('code'));
            if (c == null) {
                fail('Category ' + p.get('category') + ' not found – run the catalog step first');
                continue;
            }
            if (prod != null) {
                pcp.add(new Map<String, Object>{ 'ProductCategoryId' => c.Id, 'ProductId' => prod.Id });
            }
        }
        sync('ProductCategoryProduct', new List<String>{ 'ProductCategoryId', 'ProductId' }, pcp,
            'ProductId IN :ids', new Map<String, Object>{ 'ids' => idsOf(products.values()) }, null);

        // selling model options
        Map<String, SObject> models = byKey('ProductSellingModel', 'Name', null, null);
        Id proration = prorationPolicyId();
        List<Map<String, Object>> opts = new List<Map<String, Object>>();
        for (Map<String, Object> p : allProducts()) {
            SObject prod = products.get((String) p.get('code'));
            if (prod == null) {
                continue;
            }
            Boolean first = true;
            for (Object m : (List<Object>) p.get('sellingModels')) {
                SObject psm = models.get((String) m);
                if (psm == null) {
                    fail('Selling model ' + m + ' not found – run the catalog step first');
                    continue;
                }
                Map<String, Object> r = new Map<String, Object>{ 'Product2Id' => prod.Id,
                    'ProductSellingModelId' => psm.Id, 'IsDefault' => first };
                if (proration != null && (String) psm.get('SellingModelType') != 'OneTime') {
                    r.put('ProrationPolicyId', proration);
                }
                opts.add(r);
                first = false;
            }
        }
        sync('ProductSellingModelOption', new List<String>{ 'Product2Id', 'ProductSellingModelId' }, opts,
            'Product2Id IN :ids', new Map<String, Object>{ 'ids' => idsOf(products.values()) }, null);
    }

    /** Tier bundles (tier matrix 3.1): component groups and required / optional components. */
    public void loadBundles() {
        Map<String, SObject> products = byKey('Product2', 'ProductCode', 'ProductCode LIKE \'MB-%\'', null);
        Id relType = bundleRelationshipTypeId();
        Map<String, Object> bundles = (Map<String, Object>) data.get('bundles');

        List<Map<String, Object>> groupRows = new List<Map<String, Object>>();
        Set<Id> parentIds = new Set<Id>();
        for (String parentCode : bundles.keySet()) {
            SObject parent = products.get(parentCode);
            if (parent == null) {
                fail('Bundle ' + parentCode + ' not found – run the products step first');
                continue;
            }
            parentIds.add(parent.Id);
            Integer seq = 1;
            for (Object g : (List<Object>) bundles.get(parentCode)) {
                Map<String, Object> grp = (Map<String, Object>) g;
                groupRows.add(new Map<String, Object>{ 'ParentProductId' => parent.Id, 'Name' => grp.get('name'),
                    'Code' => parentCode + '-' + String.valueOf(grp.get('name')).replace(' ', '-').toUpperCase(),
                    'Sequence' => seq++, 'MinBundleComponents' => grp.get('min'), 'MaxBundleComponents' => grp.get('max') });
            }
        }
        Map<String, Object> scope = new Map<String, Object>{ 'ids' => parentIds };
        Map<String, SObject> groups = sync('ProductComponentGroup', new List<String>{ 'ParentProductId', 'Name' }, groupRows,
            'ParentProductId IN :ids', scope, null);

        List<Map<String, Object>> compRows = new List<Map<String, Object>>();
        Map<Id, Set<Id>> wanted = new Map<Id, Set<Id>>();
        for (String parentCode : bundles.keySet()) {
            SObject parent = products.get(parentCode);
            if (parent == null) {
                continue;
            }
            wanted.put(parent.Id, new Set<Id>());
            Integer seq = 1;
            for (Object g : (List<Object>) bundles.get(parentCode)) {
                Map<String, Object> grp = (Map<String, Object>) g;
                SObject grpRec = groups.get(parent.Id + '|' + grp.get('name'));
                for (Object c : (List<Object>) grp.get('components')) {
                    Map<String, Object> comp = (Map<String, Object>) c;
                    SObject child = products.get((String) comp.get('code'));
                    if (child == null) {
                        fail(parentCode + ': component ' + comp.get('code') + ' not found');
                        continue;
                    }
                    wanted.get(parent.Id).add(child.Id);
                    Boolean required = comp.get('required') == true;
                    compRows.add(new Map<String, Object>{
                        'ParentProductId' => parent.Id, 'ChildProductId' => child.Id,
                        'ProductComponentGroupId' => grpRec == null ? null : grpRec.Id,
                        'ProductRelationshipTypeId' => relType,
                        'IsComponentRequired' => required, 'IsDefaultComponent' => comp.get('default') == true,
                        'Quantity' => 1, 'MinQuantity' => required ? 1 : 0, 'MaxQuantity' => comp.get('scale') == 'Constant' ? 1 : null,
                        'QuantityScaleMethod' => comp.get('scale'), 'DoesBundlePriceIncludeChild' => required,
                        'IsQuantityEditable' => !required, 'Sequence' => seq++ });
                }
            }
        }
        sync('ProductRelatedComponent', new List<String>{ 'ParentProductId', 'ChildProductId' }, compRows,
            'ParentProductId IN :ids', scope, null);

        // report components that are in the org but not in the spec (e.g. AI Concierge add-on on Ultimate, CR-05)
        for (SObject extra : Database.queryWithBinds(
                'SELECT Id, ParentProduct.ProductCode, ChildProduct.ProductCode, ParentProductId, ChildProductId'
                + ' FROM ProductRelatedComponent WHERE ParentProductId IN :ids', scope, AccessLevel.SYSTEM_MODE)) {
            Set<Id> ok = wanted.get((Id) extra.get('ParentProductId'));
            if (ok != null && !ok.contains((Id) extra.get('ChildProductId'))) {
                fail('Not in spec – remove by hand: component ' + extra.getSObject('ChildProduct').get('ProductCode')
                    + ' on bundle ' + extra.getSObject('ParentProduct').get('ProductCode') + ' (' + extra.Id + ')');
            }
        }
    }

    /** Attribute picklists, values, definitions, and product attribute assignments (spec 12.6). */
    public void loadAttributes() {
        List<Map<String, Object>> picklists = new List<Map<String, Object>>();
        for (Object o : listOf('attributes')) {
            Map<String, Object> a = (Map<String, Object>) o;
            if (a.get('type') == 'Picklist') {
                picklists.add(new Map<String, Object>{ 'Name' => a.get('name') + ' Values', 'DataType' => 'Text',
                    'Status' => 'Active', 'Description' => 'Values for the ' + a.get('name') + ' attribute' });
            }
        }
        Map<String, SObject> lists = sync('AttributePicklist', new List<String>{ 'Name' }, picklists, null, null, null);

        List<Map<String, Object>> values = new List<Map<String, Object>>();
        List<Map<String, Object>> defs = new List<Map<String, Object>>();
        for (Object o : listOf('attributes')) {
            Map<String, Object> a = (Map<String, Object>) o;
            Map<String, Object> d = new Map<String, Object>{ 'Name' => a.get('name'), 'Label' => a.get('name'),
                'DeveloperName' => a.get('code'), 'Code' => a.get('code'), 'DataType' => a.get('type'),
                'IsActive' => true, 'Description' => 'Used by: ' + a.get('usedBy') };
            if (a.get('type') == 'Picklist') {
                SObject pl = lists.get(a.get('name') + ' Values');
                if (pl == null) {
                    continue;
                }
                d.put('PicklistId', pl.Id);
                Integer seq = 1;
                for (Object v : (List<Object>) a.get('values')) {
                    values.add(new Map<String, Object>{ 'PicklistId' => pl.Id, 'Name' => v, 'Value' => v,
                        'Code' => String.valueOf(v).toUpperCase(), 'Sequence' => seq++, 'Status' => 'Active' });
                }
            }
            defs.add(d);
        }
        sync('AttributePicklistValue', new List<String>{ 'PicklistId', 'Value' }, values,
            'PicklistId IN :ids', new Map<String, Object>{ 'ids' => idsOf(lists.values()) }, null);
        Map<String, SObject> attrDefs = sync('AttributeDefinition', new List<String>{ 'Name' }, defs, null, null,
            new Set<String>{ 'DeveloperName', 'DataType', 'PicklistId' });

        Map<String, SObject> products = byKey('Product2', 'ProductCode', 'ProductCode LIKE \'MB-%\'', null);
        List<Map<String, Object>> pads = new List<Map<String, Object>>();
        Integer seq = 1;
        for (Object o : listOf('productAttributes')) {
            Map<String, Object> pa = (Map<String, Object>) o;
            SObject prod = products.get((String) pa.get('product'));
            SObject def = attrDefs.get((String) pa.get('attribute'));
            if (prod == null || def == null) {
                fail('Product attribute ' + pa.get('product') + ' / ' + pa.get('attribute') + ': product or attribute missing');
                continue;
            }
            pads.add(new Map<String, Object>{ 'Product2Id' => prod.Id, 'AttributeDefinitionId' => def.Id,
                'DefaultValue' => pa.get('default'), 'IsRequired' => false, 'Sequence' => seq++, 'Status' => 'Active' });
        }
        sync('ProductAttributeDefinition', new List<String>{ 'Product2Id', 'AttributeDefinitionId' }, pads,
            'Product2Id IN :ids', new Map<String, Object>{ 'ids' => idsOf(products.values()) }, null);
    }

    /** Regional price books; one entry per product x currency x selling model, standard price book first. */
    public void loadPriceBooks() {
        List<Map<String, Object>> books = new List<Map<String, Object>>();
        for (Object o : listOf('priceBooks')) {
            Map<String, Object> b = (Map<String, Object>) o;
            books.add(new Map<String, Object>{ 'Name' => b.get('name'), 'IsActive' => true,
                'Description' => 'Mindbody list prices in ' + b.get('currency') + ' (PRC-01).' });
        }
        Map<String, SObject> pbs = sync('Pricebook2', new List<String>{ 'Name' }, books, null, null, null);

        Id stdId = standardPricebookId();
        Boolean multiCurrency = fields('PricebookEntry').containsKey('currencyisocode');
        Set<String> activeCurrencies = activeCurrencies();
        String corporate = UserInfo.getDefaultCurrency();

        Map<String, SObject> products = byKey('Product2', 'ProductCode', 'ProductCode LIKE \'MB-%\'', null);
        Map<String, SObject> models = byKey('ProductSellingModel', 'Name', null, null);
        List<Map<String, Object>> std = new List<Map<String, Object>>();
        List<Map<String, Object>> custom = new List<Map<String, Object>>();
        for (Map<String, Object> p : allProducts()) {
            SObject prod = products.get((String) p.get('code'));
            if (prod == null) {
                fail('Product ' + p.get('code') + ' not found – run the products step first');
                continue;
            }
            Map<String, Object> prices = (Map<String, Object>) p.get('prices');
            for (Object o : listOf('priceBooks')) {
                Map<String, Object> b = (Map<String, Object>) o;
                String cur = (String) b.get('currency');
                if (multiCurrency ? !activeCurrencies.contains(cur) : cur != corporate) {
                    warn('Currency ' + cur + ' is not active in this org – ' + b.get('name') + ' entries skipped (enable multi-currency and add ' + cur + ')');
                    continue;
                }
                SObject book = pbs.get((String) b.get('name'));
                for (Object m : (List<Object>) p.get('sellingModels')) {
                    SObject psm = models.get((String) m);
                    if (psm == null || book == null) {
                        continue;
                    }
                    Object price = prices.get(cur);
                    Map<String, Object> e = new Map<String, Object>{ 'Product2Id' => prod.Id,
                        'ProductSellingModelId' => psm.Id, 'UnitPrice' => price == null ? (Object) 0 : price,
                        'IsActive' => true, 'UseStandardPrice' => false };
                    if (multiCurrency) {
                        e.put('CurrencyIsoCode', cur);
                    }
                    Map<String, Object> s = e.clone();
                    s.put('Pricebook2Id', stdId);
                    std.add(s);
                    e.put('Pricebook2Id', book.Id);
                    custom.add(e);
                }
            }
        }
        List<String> key = new List<String>{ 'Pricebook2Id', 'Product2Id', 'ProductSellingModelId' };
        if (multiCurrency) {
            key.add('CurrencyIsoCode');
        }
        Map<String, Object> scope = new Map<String, Object>{ 'ids' => idsOf(products.values()) };
        sync('PricebookEntry', key, dedupe(std, key), 'Product2Id IN :ids', scope, null);
        sync('PricebookEntry', key, custom, 'Product2Id IN :ids', scope, null);
    }

    // ================================================================== ARM lookups

    Id prorationPolicyId() {
        if (!hasObject('ProrationPolicy')) {
            warn('ProrationPolicy is not available in this org – selling model options get no proration policy');
            return null;
        }
        String name = (String) ((Map<String, Object>) data.get('prorationPolicy')).get('name');
        List<SObject> found = Database.query('SELECT Id, Name FROM ProrationPolicy ORDER BY CreatedDate');
        for (SObject p : found) {
            if (p.get('Name') == name) {
                return p.Id;
            }
        }
        Map<String, SObject> created = sync('ProrationPolicy', new List<String>{ 'Name' }, new List<Map<String, Object>>{
            new Map<String, Object>{ 'Name' => name, 'ProrationPolicyType' => 'StandardTimePeriods',
                'ArePartialPeriodsAllowed' => true, 'StandardTimePeriods' => 'Daily', 'RemainderStrategy' => 'AddToFirst' }
        }, null, null, null, true);
        if (created.containsKey(name)) {
            return created.get(name).Id;
        }
        if (!found.isEmpty()) {
            warn('Could not create ' + name + ' – using existing proration policy ' + found[0].get('Name') + ' (BIL-04 needs daily proration: confirm it)');
            return found[0].Id;
        }
        return null;
    }

    Id bundleRelationshipTypeId() {
        List<SObject> types = Database.query('SELECT Id, Name, AssociatedProductRoleCat, MainProductRoleCat FROM ProductRelationshipType');
        for (SObject t : types) {
            if (t.get('AssociatedProductRoleCat') == 'BundleComponent' && t.get('MainProductRoleCat') == 'Bundle') {
                return t.Id;
            }
        }
        Map<String, SObject> created = sync('ProductRelationshipType', new List<String>{ 'Name' }, new List<Map<String, Object>>{
            new Map<String, Object>{ 'Name' => 'Bundle to Bundle Component',
                'AssociatedProductRoleCat' => 'BundleComponent', 'MainProductRoleCat' => 'Bundle' }
        }, null, null, null, true);
        return created.isEmpty() ? null : created.values()[0].Id;
    }

    static Id standardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        Pricebook2 std = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        if (!std.IsActive) {
            std.IsActive = true;
            update std;
        }
        return std.Id;
    }

    static Set<String> activeCurrencies() {
        Set<String> out = new Set<String>();
        if (!hasObject('CurrencyType')) {
            out.add(UserInfo.getDefaultCurrency());
            return out;
        }
        for (SObject c : Database.query('SELECT IsoCode FROM CurrencyType WHERE IsActive = true')) {
            out.add((String) c.get('IsoCode'));
        }
        return out;
    }

    // ================================================================== generic, release-tolerant upsert

    Map<String, SObject> sync(String obj, List<String> keyFields, List<Map<String, Object>> rows,
                              String whereClause, Map<String, Object> binds, Set<String> insertOnly) {
        return sync(obj, keyFields, rows, whereClause, binds, insertOnly, false);
    }

    /**
     * Inserts rows that are not in the org yet and updates the ones that are, matching on keyFields.
     * Returns every matched or created record keyed by the joined key values ("a|b").
     * insertOnly: fields set on create but never overwritten. createOnly: never update existing records.
     */
    Map<String, SObject> sync(String obj, List<String> keyFields, List<Map<String, Object>> rows,
                              String whereClause, Map<String, Object> binds, Set<String> insertOnly, Boolean createOnly) {
        Map<String, SObject> result = new Map<String, SObject>();
        if (!hasObject(obj)) {
            fail(obj + ' is not available in this org – is Revenue Cloud (ARM) enabled and does the user have access?');
            return result;
        }
        if (rows.isEmpty()) {
            return result;
        }
        Map<String, Schema.SObjectField> f = fields(obj);
        List<String> selectFields = new List<String>{ 'Id' };
        for (String k : keyFields) {
            if (!f.containsKey(k.toLowerCase())) {
                fail(obj + '.' + k + ' does not exist – cannot match records');
                return result;
            }
            selectFields.add(k);
        }
        if (obj == 'ProductSellingModel') {
            selectFields.add('SellingModelType');
        }
        String soql = 'SELECT ' + String.join(selectFields, ', ') + ' FROM ' + obj
            + (whereClause == null ? '' : ' WHERE ' + whereClause) + ' LIMIT 10000';
        Map<String, SObject> existing = new Map<String, SObject>();
        for (SObject r : Database.queryWithBinds(soql, binds == null ? new Map<String, Object>() : binds, AccessLevel.SYSTEM_MODE)) {
            existing.put(keyOf(r, keyFields), r);
        }

        List<SObject> toInsert = new List<SObject>();
        List<SObject> toUpdate = new List<SObject>();
        List<String> insertKeys = new List<String>();
        List<String> updateKeys = new List<String>();
        Schema.SObjectType t = gd().get(obj.toLowerCase());
        for (Map<String, Object> row : rows) {
            String key = keyOfRow(row, keyFields);
            SObject current = existing.get(key);
            if (current != null) {
                result.put(key, current);
                if (createOnly == true) {
                    continue;
                }
                SObject rec = t.newSObject(current.Id);
                Boolean changed = false;
                for (String field : row.keySet()) {
                    if (insertOnly != null && insertOnly.contains(field)) {
                        continue;
                    }
                    changed = put(rec, obj, field, row.get(field), false) || changed;
                }
                if (changed) {
                    toUpdate.add(rec);
                    updateKeys.add(key);
                }
            } else {
                SObject rec = t.newSObject();
                for (String field : row.keySet()) {
                    put(rec, obj, field, row.get(field), true);
                }
                toInsert.add(rec);
                insertKeys.add(key);
            }
        }
        Integer ok = 0;
        Integer bad = 0;
        List<Database.SaveResult> ins = Database.insert(toInsert, false);
        for (Integer i = 0; i < ins.size(); i++) {
            if (ins[i].isSuccess()) {
                result.put(insertKeys[i], toInsert[i]);
                ok++;
            } else {
                bad++;
                fail(obj + ' [' + insertKeys[i] + '] insert failed: ' + messages(ins[i].getErrors()));
            }
        }
        Integer upd = 0;
        List<Database.SaveResult> ups = Database.update(toUpdate, false);
        for (Integer i = 0; i < ups.size(); i++) {
            if (ups[i].isSuccess()) {
                upd++;
            } else {
                bad++;
                fail(obj + ' [' + updateKeys[i] + '] update failed: ' + messages(ups[i].getErrors()));
            }
        }
        info(obj + ': ' + ok + ' created, ' + upd + ' updated, ' + (rows.size() - ok - upd - bad) + ' unchanged, ' + bad + ' failed');
        return result;
    }

    /** Sets a field if it exists and is writable; returns true when it was set. */
    Boolean put(SObject rec, String obj, String field, Object value, Boolean creating) {
        Schema.SObjectField sf = fields(obj).get(field.toLowerCase());
        if (sf == null) {
            warn(obj + '.' + field + ' does not exist in this org – skipped');
            return false;
        }
        Schema.DescribeFieldResult d = sf.getDescribe();
        if (creating ? !d.isCreateable() : !d.isUpdateable()) {
            if (creating) {
                warn(obj + '.' + field + ' is not writable – skipped');
            }
            return false;
        }
        if (value == null && creating) {
            return false;
        }
        rec.put(field, coerce(d.getType(), value));
        return true;
    }

    static Object coerce(Schema.DisplayType t, Object v) {
        if (v == null) {
            return null;
        }
        String text = String.valueOf(v);
        if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.PERCENT) {
            return Decimal.valueOf(text);
        }
        if (t == Schema.DisplayType.INTEGER) {
            return Integer.valueOf(text);
        }
        if (t == Schema.DisplayType.BOOLEAN) {
            return (v instanceof Boolean) ? v : (Object) Boolean.valueOf(text);
        }
        if (t == Schema.DisplayType.DATE) {
            return (v instanceof Date) ? v : (Object) Date.valueOf(text);
        }
        if (t == Schema.DisplayType.DATETIME) {
            return (v instanceof Datetime) ? v : (Object) Datetime.valueOf(text);
        }
        if (t == Schema.DisplayType.REFERENCE || t == Schema.DisplayType.ID) {
            return (v instanceof Id) ? v : (Object) Id.valueOf(text);
        }
        return text;
    }

    static String keyOf(SObject r, List<String> keyFields) {
        List<String> parts = new List<String>();
        for (String k : keyFields) {
            parts.add(norm(r.get(k)));
        }
        return String.join(parts, '|');
    }

    static String keyOfRow(Map<String, Object> row, List<String> keyFields) {
        List<String> parts = new List<String>();
        for (String k : keyFields) {
            parts.add(norm(row.get(k)));
        }
        return String.join(parts, '|');
    }

    /** Ids are compared in their 18-character form so 15/18-character keys match. */
    static String norm(Object v) {
        if (v == null) {
            return '';
        }
        if (v instanceof Id) {
            return String.valueOf((Id) v);
        }
        return String.valueOf(v);
    }

    Map<String, SObject> byKey(String obj, String field, String whereClause, Map<String, Object> binds) {
        Map<String, SObject> out = new Map<String, SObject>();
        if (!hasObject(obj)) {
            fail(obj + ' is not available in this org');
            return out;
        }
        String extra = obj == 'ProductSellingModel' ? ', SellingModelType' : '';
        String soql = 'SELECT Id, ' + field + extra + ' FROM ' + obj + (whereClause == null ? '' : ' WHERE ' + whereClause) + ' LIMIT 10000';
        for (SObject r : Database.queryWithBinds(soql, binds == null ? new Map<String, Object>() : binds, AccessLevel.SYSTEM_MODE)) {
            out.put((String) r.get(field), r);
        }
        return out;
    }

    static List<Map<String, Object>> dedupe(List<Map<String, Object>> rows, List<String> key) {
        Map<String, Map<String, Object>> seen = new Map<String, Map<String, Object>>();
        for (Map<String, Object> r : rows) {
            String k = keyOfRow(r, key);
            if (!seen.containsKey(k)) {
                seen.put(k, r);
            }
        }
        return seen.values();
    }

    List<Map<String, Object>> allProducts() {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Object o : listOf('products')) {
            out.add((Map<String, Object>) o);
        }
        for (Object o : listOf('features')) {
            out.add((Map<String, Object>) o);
        }
        return out;
    }

    List<Object> listOf(String key) {
        Object v = data.get(key);
        return v == null ? new List<Object>() : (List<Object>) v;
    }

    static Map<String, Object> address(Id parentId, String type, String name, Map<String, Object> a) {
        return new Map<String, Object>{ 'ParentId' => parentId, 'AddressType' => type, 'Name' => name,
            'IsPrimary' => true, 'Street' => a.get('street'), 'City' => a.get('city'), 'State' => a.get('state'),
            'PostalCode' => a.get('postalCode'), 'Country' => a.get('country') };
    }

    static Set<Id> idsOf(List<SObject> recs) {
        Set<Id> ids = new Set<Id>();
        for (SObject r : recs) {
            if (r.Id != null) {
                ids.add(r.Id);
            }
        }
        return ids;
    }

    static String messages(List<Database.Error> errs) {
        List<String> m = new List<String>();
        for (Database.Error e : errs) {
            m.add(e.getStatusCode() + ': ' + e.getMessage() + (e.getFields().isEmpty() ? '' : ' ' + e.getFields()));
        }
        return String.join(m, '; ');
    }

    // ================================================================== describe cache + logging

    static Map<String, Schema.SObjectType> gdCache;
    static Map<String, Map<String, Schema.SObjectField>> fieldCache = new Map<String, Map<String, Schema.SObjectField>>();

    static Map<String, Schema.SObjectType> gd() {
        if (gdCache == null) {
            gdCache = Schema.getGlobalDescribe();
        }
        return gdCache;
    }

    static Boolean hasObject(String obj) {
        return gd().containsKey(obj.toLowerCase());
    }

    static Map<String, Schema.SObjectField> fields(String obj) {
        String k = obj.toLowerCase();
        if (!fieldCache.containsKey(k)) {
            fieldCache.put(k, gd().get(k).getDescribe().fields.getMap());
        }
        return fieldCache.get(k);
    }

    void info(String m) { log.add('  ' + m); }
    void warn(String m) {
        if (warned.add(m)) {
            log.add('  WARNING ' + m);
        }
    }
    void fail(String m) {
        errors++;
        log.add('  ERROR ' + m);
    }
}
