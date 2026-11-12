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
    public static final List<String> STEPS = new List<String>{ 'inventory', 'accounts', 'catalog', 'products', 'bundles', 'attributes', 'pricebooks', 'pricingschedules', 'constraints', 'constraints-reset' };

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
            when 'inventory' { inventory(); }
            when 'pricingschedules' { loadPricingSchedules(); }
            when 'constraints' { loadConstraintLinks(); }
            when 'constraints-reset' { resetConstraintLinks(); }
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
                    'Industry' => a.get('vertical')
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

        sellingModels(true);
        prorationPolicyId();
    }

    /** Products and feature components, category assignment and selling model options. */
    public void loadProducts() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Map<String, Object> p : allProducts()) {
            Boolean bundle = p.get('bundle') == true;
            Map<String, Object> r = new Map<String, Object>{
                'Name' => p.get('name'), 'ProductCode' => p.get('code'), 'Description' => p.get('description'),
                'IsActive' => true, 'Family' => p.get('productType'),
                'Allowed_Billing_Frequencies__c' => p.get('billingFrequencies'),
                'Allowed_Term_Months__c' => p.get('allowedTermMonths'),
                'QuantityUnitOfMeasure' => p.get('unitOfMeasure'), 'Integration_Status__c' => 'New',
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
        Map<String, SObject> models = sellingModels(false);
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

        // The products step sets Type only when it creates a product; a product that later becomes a bundle
        // (Branded app, CR-08) is switched here.
        List<Product2> toBundle = new List<Product2>();
        for (Product2 p : [SELECT Id, ProductCode, Type, ConfigureDuringSale FROM Product2 WHERE ProductCode IN :bundles.keySet()]) {
            if (p.Type != 'Bundle') {
                toBundle.add(new Product2(Id = p.Id, Type = 'Bundle', ConfigureDuringSale = 'Allowed'));
            }
        }
        if (!toBundle.isEmpty()) {
            Integer i = 0;
            for (Database.SaveResult r : Database.update(toBundle, false)) {
                if (r.isSuccess()) {
                    info('Product ' + toBundle[i].Id + ' is now a bundle');
                } else {
                    fail('Could not make product ' + toBundle[i].Id + ' a bundle: ' + r.getErrors()[0].getMessage());
                }
                i++;
            }
        }

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
                        // Quantities are never edited by reps: included features and AI Concierge follow the
                        // tier's location count (Proportional, CR-06), Branded app stays at 1 (Constant, CR-07).
                        // ARM only accepts Min/MaxQuantity when IsQuantityEditable is true, so they are not set.
                        'Quantity' => 1, 'QuantityScaleMethod' => comp.get('scale'),
                        // included features are priced in the bundle ($0); a required child with its own price
                        // (Branded app setup, CR-08) sets priceIncluded false
                        'DoesBundlePriceIncludeChild' => comp.containsKey('priceIncluded') ? comp.get('priceIncluded') == true : required,
                        'IsQuantityEditable' => false, 'Sequence' => seq++ });
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

    /**
     * Constraint model product links (spec 12.3): one "Type" link per CML type -> product.
     * The model itself (CML text) is created in Setup > Constraint Models; the CML text cannot be written by API.
     */
    public void loadConstraintLinks() {
        Map<String, SObject> products = byKey('Product2', 'ProductCode', 'ProductCode LIKE \'MB-%\'', null);
        for (Object o : listOf('constraintModels')) {
            Map<String, Object> m = (Map<String, Object>) o;
            String apiName = (String) m.get('apiName');
            // match on API name or label, ignoring case, spaces and underscores (Setup may add an underscore)
            String want = apiName.replaceAll('[\\s_]', '').toLowerCase();
            Id setId = null;
            List<String> seen = new List<String>();
            for (SObject es : Database.query('SELECT Id, Name, ApiName FROM ExpressionSet WHERE InterfaceSourceType = \'Constraint\'')) {
                seen.add(es.get('Name') + ' (' + es.get('ApiName') + ')');
                for (String k : new List<String>{ 'ApiName', 'Name' }) {
                    String v = (String) es.get(k);
                    if (v != null && v.replaceAll('[\\s_]', '').toLowerCase() == want) {
                        setId = es.Id;
                    }
                }
            }
            if (setId == null) {
                fail('Constraint model ' + apiName + ' not found – constraint models in the org: ' + String.join(seen, ', '));
                continue;
            }
            info('Constraint model ' + apiName + ' = ' + setId);
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            Map<String, Object> types = (Map<String, Object>) m.get('types');
            for (String tag : types.keySet()) {
                SObject p = products.get((String) types.get(tag));
                if (p == null) {
                    fail(apiName + ': product ' + types.get(tag) + ' for type ' + tag + ' not found');
                    continue;
                }
                rows.add(new Map<String, Object>{ 'ExpressionSetId' => setId, 'ConstraintModelTag' => tag,
                    'ConstraintModelTagType' => 'Type', 'ReferenceObjectId' => p.Id });
            }
            sync('ExpressionSetConstraintObj', new List<String>{ 'ExpressionSetId', 'ConstraintModelTag' }, rows,
                'ExpressionSetId = :sid', new Map<String, Object>{ 'sid' => setId }, null);
        }
    }

    /**
     * Deletes the product links of the Mindbody constraint models. Saving the CML in the constraint model editor
     * creates the component types itself and fails ("Component Type ... already exists") when links were added first.
     */
    public void resetConstraintLinks() {
        for (Object o : listOf('constraintModels')) {
            String want = ((String) ((Map<String, Object>) o).get('apiName')).replaceAll('[\\s_]', '').toLowerCase();
            for (SObject es : Database.query('SELECT Id, ApiName, Name FROM ExpressionSet WHERE InterfaceSourceType = \'Constraint\'')) {
                String a = ((String) es.get('ApiName')).replaceAll('[\\s_]', '').toLowerCase();
                if (a != want) {
                    continue;
                }
                List<SObject> links = Database.query('SELECT Id, ConstraintModelTag FROM ExpressionSetConstraintObj WHERE ExpressionSetId = \'' + es.Id + '\'');
                Integer ok = 0;
                for (Database.DeleteResult r : Database.delete(links, false)) {
                    if (r.isSuccess()) { ok++; } else { fail('Delete link ' + r.getId() + ': ' + r.getErrors()[0].getMessage()); }
                }
                info(es.get('Name') + ': ' + ok + ' of ' + links.size() + ' product links deleted');
            }
        }
    }

    /** Attribute picklists, values, definitions, and product attribute assignments (spec 12.6). */
    public void loadAttributes() {
        List<Map<String, Object>> picklists = new List<Map<String, Object>>();
        for (Object o : listOf('attributes')) {
            Map<String, Object> a = (Map<String, Object>) o;
            if (a.get('type') == 'Picklist') {
                picklists.add(new Map<String, Object>{ 'Name' => a.get('name') + ' Values', 'Code' => a.get('code') + '_VALUES', 'DataType' => 'Text',
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
                        'Code' => valueCode((String) a.get('code'), v), 'Sequence' => seq++, 'Status' => 'Active' });
                }
            }
            defs.add(d);
        }
        sync('AttributePicklistValue', new List<String>{ 'PicklistId', 'Value' }, values,
            'PicklistId IN :ids', new Map<String, Object>{ 'ids' => idsOf(lists.values()) }, null);
        Map<String, String> renamed = reuseExistingAttributes(defs);
        Map<String, SObject> attrDefs = sync('AttributeDefinition', new List<String>{ 'Name' }, defs, null, null,
            new Set<String>{ 'DeveloperName', 'DataType', 'PicklistId' });

        // ARM attaches attributes through product classifications: classification -> attributes,
        // product.BasedOnId -> classification; product-level defaults override the classification's.
        Map<String, SObject> products = byKey('Product2', 'ProductCode', 'ProductCode LIKE \'MB-%\'', null);
        List<Map<String, Object>> classRows = new List<Map<String, Object>>();
        for (Object o : listOf('classifications')) {
            Map<String, Object> c = (Map<String, Object>) o;
            // created as Draft so attributes can be added, activated below
            classRows.add(new Map<String, Object>{ 'Name' => c.get('name'), 'Code' => c.get('code'), 'Status' => 'Draft' });
        }
        Map<String, SObject> classes = sync('ProductClassification', new List<String>{ 'Name' }, classRows, null, null,
            new Set<String>{ 'Status' });

        List<Map<String, Object>> classAttrs = new List<Map<String, Object>>();
        for (Object o : listOf('classifications')) {
            Map<String, Object> c = (Map<String, Object>) o;
            SObject cls = classes.get((String) c.get('name'));
            if (cls == null) {
                continue;
            }
            Integer seq = 1;
            for (Object ao : (List<Object>) c.get('attributes')) {
                Map<String, Object> a = (Map<String, Object>) ao;
                SObject def = attrDefs.get(resolved(renamed, (String) a.get('attribute')));
                if (def == null) {
                    fail('Classification ' + c.get('name') + ': attribute ' + a.get('attribute') + ' missing');
                    continue;
                }
                classAttrs.add(new Map<String, Object>{ 'ProductClassificationId' => cls.Id, 'AttributeDefinitionId' => def.Id,
                    'Name' => a.get('attribute'), 'DefaultValue' => a.get('default'), 'IsRequired' => false,
                    'Sequence' => seq++, 'Status' => 'Active' });
            }
        }
        Map<String, SObject> pcas = sync('ProductClassificationAttr',
            new List<String>{ 'ProductClassificationId', 'AttributeDefinitionId' }, classAttrs,
            'ProductClassificationId IN :ids', new Map<String, Object>{ 'ids' => idsOf(classes.values()) }, null);

        List<Map<String, Object>> toActivate = new List<Map<String, Object>>();
        for (String n : classes.keySet()) {
            toActivate.add(new Map<String, Object>{ 'Name' => n, 'Status' => 'Active' });
        }
        sync('ProductClassification', new List<String>{ 'Name' }, toActivate, null, null, null);

        // base each product on its classification
        Schema.SObjectField basedOnField = fields('Product2').get('basedonid');
        if (basedOnField == null || !basedOnField.getDescribe().isUpdateable()) {
            fail('Product2.BasedOnId is missing or not editable – set each product\'s classification in the product record by hand');
        }
        List<Map<String, Object>> basedOn = new List<Map<String, Object>>();
        Map<String, Id> classOfProduct = new Map<String, Id>();
        for (Object o : listOf('classifications')) {
            Map<String, Object> c = (Map<String, Object>) o;
            SObject cls = classes.get((String) c.get('name'));
            for (Object code : (List<Object>) c.get('products')) {
                if (cls != null && products.containsKey((String) code)) {
                    basedOn.add(new Map<String, Object>{ 'ProductCode' => code, 'BasedOnId' => cls.Id });
                    classOfProduct.put((String) code, cls.Id);
                }
            }
        }
        sync('Product2', new List<String>{ 'ProductCode' }, basedOn, 'ProductCode LIKE \'MB-%\'', null, null);

        // product-level default overrides (e.g. Ultimate SMS allowance 1000)
        List<Map<String, Object>> pads = new List<Map<String, Object>>();
        for (Object o : listOf('productAttributes')) {
            Map<String, Object> pa = (Map<String, Object>) o;
            String code = (String) pa.get('product');
            String attrName = resolved(renamed, (String) pa.get('attribute'));
            SObject prod = products.get(code);
            SObject def = attrDefs.get(attrName);
            Id clsId = classOfProduct.get(code);
            SObject pca = (def == null || clsId == null) ? null : pcas.get(String.valueOf(clsId) + '|' + String.valueOf(def.Id));
            if (prod == null || pca == null) {
                fail('Product attribute ' + code + ' / ' + pa.get('attribute') + ': product, attribute or classification attribute missing');
                continue;
            }
            pads.add(new Map<String, Object>{ 'Product2Id' => prod.Id, 'AttributeDefinitionId' => def.Id,
                'ProductClassificationAttributeId' => pca.Id, 'Name' => attrName,
                'DefaultValue' => pa.get('default'), 'IsRequired' => false, 'Status' => 'Active' });
        }
        sync('ProductAttributeDefinition', new List<String>{ 'Product2Id', 'AttributeDefinitionId' }, pads,
            'Product2Id IN :ids', new Map<String, Object>{ 'ids' => idsOf(products.values()) }, null);
    }

    /** Picklist value codes are unique across the org, so they carry the attribute: MB_CARD_PRESENT_YES. */
    static String valueCode(String attributeCode, Object value) {
        return (attributeCode + '_' + String.valueOf(value)).toUpperCase().replaceAll('[^A-Z0-9]+', '_');
    }

    static String resolved(Map<String, String> renamed, String name) {
        return renamed.containsKey(name) ? renamed.get(name) : name;
    }

    /**
     * Standard ARM pricing records for the spec 12.2 waterfall – no custom objects:
     *   Price Adjustment Schedules + Tiers   volume by hierarchy locations, contract term, billing frequency
     *   Price book "Mindbody Floor Prices"   tier floor per location per month (PRC-18)
     *   Promotions + targets + coupons       LAUNCH3, SWITCH50, GROW2 (PRC-07)
     * Tiers are created per product x selling model x currency, as the standard tier decision table matches on them.
     */
    public void loadPricingSchedules() {
        Map<String, Object> pricing = (Map<String, Object>) data.get('pricing');
        Map<String, SObject> products = byKey('Product2', 'ProductCode', 'ProductCode LIKE \'MB-%\'', null);
        Map<String, SObject> models = sellingModels(false);
        Set<String> currencies = new Set<String>();
        for (Object o : listOf('priceBooks')) {
            currencies.add((String) ((Map<String, Object>) o).get('currency'));
        }
        if (fields('PricebookEntry').containsKey('currencyisocode')) {
            currencies.retainAll(activeCurrencies());
        } else {
            currencies = new Set<String>{ UserInfo.getDefaultCurrency() };
        }
        Boolean multiCurrency = fields('PriceAdjustmentTier').containsKey('currencyisocode');

        // 1. schedules
        List<Map<String, Object>> schedRows = new List<Map<String, Object>>();
        for (Object o : (List<Object>) pricing.get('schedules')) {
            Map<String, Object> sc = (Map<String, Object>) o;
            // ARM: a schedule cannot be activated without tiers, and tiers cannot change while it is active.
            // So: schedule inactive -> tiers -> activate (re-runs deactivate first).
            schedRows.add(new Map<String, Object>{ 'Name' => sc.get('name'), 'ScheduleType' => sc.get('scheduleType'),
                'AdjustmentMethod' => 'Range', 'IsActive' => false, 'Description' => sc.get('input'),
                'EffectiveFrom' => Datetime.newInstanceGmt(2026, 1, 1) });
        }
        replaceSchedulesWithWrongType(schedRows);
        Map<String, SObject> schedules = sync('PriceAdjustmentSchedule', new List<String>{ 'Name' }, schedRows, null, null,
            new Set<String>{ 'ScheduleType' });

        // 2. tiers: schedule x product x selling model x currency x band
        Map<String, Object> productData = new Map<String, Object>();
        for (Map<String, Object> pd : allProducts()) {
            productData.put((String) pd.get('code'), pd);
        }
        List<Map<String, Object>> tierRows = new List<Map<String, Object>>();
        for (Object o : (List<Object>) pricing.get('schedules')) {
            Map<String, Object> sc = (Map<String, Object>) o;
            SObject sched = schedules.get((String) sc.get('name'));
            if (sched == null) {
                continue;
            }
            for (Object codeObj : (List<Object>) pricing.get('discountedProducts')) {
                String code = (String) codeObj;
                SObject prod = products.get(code);
                Map<String, Object> pd = (Map<String, Object>) productData.get(code);
                if (prod == null || pd == null) {
                    fail('Tier: product ' + code + ' not found – run the products step first');
                    continue;
                }
                for (Object m : (List<Object>) pd.get('sellingModels')) {
                    SObject psm = models.get((String) m);
                    if (psm == null) {
                        continue;
                    }
                    for (String cur : currencies) {
                        for (Object b : (List<Object>) sc.get('tiers')) {
                            List<Object> band = (List<Object>) b;
                            Map<String, Object> r = new Map<String, Object>{
                                'Name' => sc.get('name') + ' ' + code + ' ' + band[0] + '-' + band[1],
                                'PriceAdjustmentScheduleId' => sched.Id, 'Product2Id' => prod.Id,
                                'ProductSellingModelId' => psm.Id, 'LowerBound' => band[0], 'UpperBound' => band[1],
                                'TierType' => 'AdjustmentPercentage', 'TierValue' => band[2],
                                'ScheduleType' => sc.get('scheduleType'),
                                'EffectiveFrom' => Datetime.newInstanceGmt(2026, 1, 1) };
                            if (multiCurrency) {
                                r.put('CurrencyIsoCode', cur);
                            }
                            tierRows.add(r);
                        }
                    }
                }
            }
        }
        List<String> tierKey = new List<String>{ 'PriceAdjustmentScheduleId', 'Product2Id', 'ProductSellingModelId', 'LowerBound' };
        if (multiCurrency) {
            tierKey.add('CurrencyIsoCode');
        }
        sync('PriceAdjustmentTier', tierKey, tierRows, 'PriceAdjustmentScheduleId IN :ids',
            new Map<String, Object>{ 'ids' => idsOf(schedules.values()) }, null);

        List<Map<String, Object>> activateRows = new List<Map<String, Object>>();
        for (String n : schedules.keySet()) {
            activateRows.add(new Map<String, Object>{ 'Name' => n, 'IsActive' => true });
        }
        sync('PriceAdjustmentSchedule', new List<String>{ 'Name' }, activateRows, null, null, null);

        // 3. floor price book (standard Pricebook2 + PricebookEntry)
        Map<String, Object> floor = (Map<String, Object>) pricing.get('floorPriceBook');
        Map<String, SObject> fpb = sync('Pricebook2', new List<String>{ 'Name' }, new List<Map<String, Object>>{
            new Map<String, Object>{ 'Name' => floor.get('name'), 'IsActive' => true, 'Description' => floor.get('description') }
        }, null, null, null);
        SObject floorBook = fpb.get((String) floor.get('name'));
        Boolean pbeMulti = fields('PricebookEntry').containsKey('currencyisocode');
        List<Map<String, Object>> floorRows = new List<Map<String, Object>>();
        Map<String, Object> floorPrices = (Map<String, Object>) floor.get('prices');
        for (String code : floorPrices.keySet()) {
            SObject prod = products.get(code);
            Map<String, Object> pd = (Map<String, Object>) productData.get(code);
            if (prod == null || pd == null || floorBook == null) {
                continue;
            }
            Map<String, Object> byCur = (Map<String, Object>) floorPrices.get(code);
            for (Object m : (List<Object>) pd.get('sellingModels')) {
                SObject psm = models.get((String) m);
                for (String cur : currencies) {
                    if (psm == null || !byCur.containsKey(cur)) {
                        continue;
                    }
                    Map<String, Object> e = new Map<String, Object>{ 'Pricebook2Id' => floorBook.Id, 'Product2Id' => prod.Id,
                        'ProductSellingModelId' => psm.Id, 'UnitPrice' => byCur.get(cur), 'IsActive' => true, 'UseStandardPrice' => false };
                    if (pbeMulti) {
                        e.put('CurrencyIsoCode', cur);
                    }
                    floorRows.add(e);
                }
            }
        }
        List<String> pbeKey = new List<String>{ 'Pricebook2Id', 'Product2Id', 'ProductSellingModelId' };
        if (pbeMulti) {
            pbeKey.add('CurrencyIsoCode');
        }
        if (floorBook != null) {
            sync('PricebookEntry', pbeKey, floorRows, 'Pricebook2Id = :pb', new Map<String, Object>{ 'pb' => floorBook.Id }, null);
        }

        // 4. promotions (standard Promotion, PromotionTarget, Coupon)
        if (!hasObject('Promotion')) {
            warn('Promotion is not available – turn on Promotions in Setup, then re-run this step');
            return;
        }
        List<Map<String, Object>> promoRows = new List<Map<String, Object>>();
        for (Object o : (List<Object>) pricing.get('promotions')) {
            Map<String, Object> pr = (Map<String, Object>) o;
            promoRows.add(new Map<String, Object>{ 'Name' => pr.get('name'), 'DisplayName' => pr.get('displayName'),
                'Description' => pr.get('displayName') + '. Conditions: ' + pr.get('conditions')
                    + '. Applies for ' + pr.get('months') + ' months (PRC-07).',
                'IsActive' => true, 'IsAutomatic' => false, 'ExclusivityType' => 'No',
                'StartDate' => Date.newInstance(2026, 1, 1), 'StartDateTime' => Datetime.newInstanceGmt(2026, 1, 1) });
        }
        Map<String, SObject> promos = sync('Promotion', new List<String>{ 'Name' }, promoRows, null, null, null);
        List<Map<String, Object>> targetRows = new List<Map<String, Object>>();
        List<Map<String, Object>> couponRows = new List<Map<String, Object>>();
        for (Object o : (List<Object>) pricing.get('promotions')) {
            Map<String, Object> pr = (Map<String, Object>) o;
            SObject promo = promos.get((String) pr.get('name'));
            if (promo == null) {
                continue;
            }
            for (Object t : (List<Object>) pr.get('targets')) {
                SObject prod = products.get((String) t);
                if (prod == null) {
                    continue;
                }
                Map<String, Object> r = new Map<String, Object>{ 'PromotionId' => promo.Id, 'Name' => pr.get('name') + ' ' + t,
                    'TargetType' => 'Product', 'TargetId' => prod.Id, 'AdjustmentType' => pr.get('adjustmentType') };
                if (pr.get('amount') != null) {
                    r.put('AdjustmentAmount', pr.get('amount'));
                }
                if (pr.get('percent') != null) {
                    r.put('AdjustmentPercent', pr.get('percent'));
                }
                targetRows.add(r);
            }
            couponRows.add(new Map<String, Object>{ 'PromotionId' => promo.Id, 'Name' => pr.get('coupon'),
                'CouponCode' => pr.get('coupon'), 'Status' => 'Active', 'StartDateTime' => Datetime.newInstanceGmt(2026, 1, 1) });
        }
        Map<String, Object> promoScope = new Map<String, Object>{ 'ids' => idsOf(promos.values()) };
        sync('PromotionTarget', new List<String>{ 'PromotionId', 'TargetId' }, targetRows, 'PromotionId IN :ids', promoScope, null);
        if (hasObject('Coupon')) {
            sync('Coupon', new List<String>{ 'CouponCode' }, couponRows, 'PromotionId IN :ids', promoScope, null);
        }
    }

    /**
     * A schedule's type cannot change after it is created. When the build data asks for another type and the
     * schedule has no tiers yet, the old schedule is deleted so it can be recreated; otherwise it is reported.
     */
    void replaceSchedulesWithWrongType(List<Map<String, Object>> schedRows) {
        Map<String, String> wanted = new Map<String, String>();
        for (Map<String, Object> r : schedRows) {
            wanted.put((String) r.get('Name'), (String) r.get('ScheduleType'));
        }
        Set<String> names = wanted.keySet();
        List<SObject> toDelete = new List<SObject>();
        List<SObject> existing = Database.query('SELECT Id, Name, ScheduleType FROM PriceAdjustmentSchedule WHERE Name IN :names');
        Set<Id> ids = idsOf(existing);
        Set<Id> withTiers = new Set<Id>();
        for (SObject t : Database.query('SELECT PriceAdjustmentScheduleId FROM PriceAdjustmentTier WHERE PriceAdjustmentScheduleId IN :ids')) {
            withTiers.add((Id) t.get('PriceAdjustmentScheduleId'));
        }
        for (SObject sc : existing) {
            String n = (String) sc.get('Name');
            if (sc.get('ScheduleType') == wanted.get(n)) {
                continue;
            }
            if (!withTiers.contains(sc.Id)) {
                info('PriceAdjustmentSchedule ' + n + ': type ' + sc.get('ScheduleType') + ' -> ' + wanted.get(n) + ', recreated');
                toDelete.add(sc);
            } else {
                fail('PriceAdjustmentSchedule ' + n + ' is type ' + sc.get('ScheduleType') + ' and has tiers; expected '
                    + wanted.get(n) + ' – delete it in Setup and re-run');
            }
        }
        if (!toDelete.isEmpty()) {
            for (Database.DeleteResult r : Database.delete(toDelete, false)) {
                if (!r.isSuccess()) {
                    fail('PriceAdjustmentSchedule delete failed: ' + messages(r.getErrors()));
                }
            }
        }
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
        Map<String, SObject> models = sellingModels(false);
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

    /**
     * ARM allows one selling model per (type, pricing term, pricing term unit), so selling models are matched
     * on that combination, not on name: an org that already has e.g. a TermDefined / 1 / Months model under
     * another name reuses it. Returns the build's model name (e.g. 'Term Monthly') -> the org's record.
     * create = true adds the combinations the org does not have yet (catalog step only).
     */
    Map<String, SObject> sellingModels(Boolean create) {
        Map<String, SObject> out = new Map<String, SObject>();
        if (!hasObject('ProductSellingModel')) {
            fail('ProductSellingModel is not available in this org');
            return out;
        }
        Map<String, SObject> byCombo = new Map<String, SObject>();
        for (SObject r : Database.query('SELECT Id, Name, SellingModelType, PricingTerm, PricingTermUnit, Status'
                + ' FROM ProductSellingModel ORDER BY CreatedDate')) {
            String k = psmKey(r.get('SellingModelType'), r.get('PricingTerm'), r.get('PricingTermUnit'));
            if (!byCombo.containsKey(k) || r.get('Status') == 'Active' && byCombo.get(k).get('Status') != 'Active') {
                byCombo.put(k, r);
            }
        }
        List<Map<String, Object>> toCreate = new List<Map<String, Object>>();
        for (Object o : listOf('sellingModels')) {
            Map<String, Object> m = (Map<String, Object>) o;
            String name = (String) m.get('name');
            String k = psmKey(m.get('type'), m.get('pricingTerm'), m.get('pricingTermUnit'));
            SObject found = byCombo.get(k);
            if (found != null) {
                out.put(name, found);
                if (create) {
                    info('ProductSellingModel ' + name + ': using existing "' + found.get('Name') + '" (' + found.get('Status') + ')'
                        + (found.get('Status') == 'Active' ? '' : ' – ACTIVATE it in Setup'));
                }
            } else if (create) {
                Map<String, Object> r = new Map<String, Object>{ 'Name' => name, 'SellingModelType' => m.get('type'), 'Status' => 'Active' };
                if (m.get('pricingTerm') != null) {
                    r.put('PricingTerm', m.get('pricingTerm'));
                    r.put('PricingTermUnit', m.get('pricingTermUnit'));
                }
                toCreate.add(r);
            } else {
                fail('Selling model ' + name + ' (' + k + ') not found – run the catalog step first');
            }
        }
        if (!toCreate.isEmpty()) {
            Map<String, SObject> created = sync('ProductSellingModel', new List<String>{ 'Name' }, toCreate, null, null, null, true);
            for (String name : created.keySet()) {
                out.put(name, created.get(name));
            }
        }
        return out;
    }

    static String psmKey(Object modelType, Object term, Object unit) {
        String t = modelType == null ? '' : String.valueOf(modelType);
        if (t == 'OneTime') {
            return 'OneTime';   // one-time models have no pricing term
        }
        String n = term == null ? '' : String.valueOf(Decimal.valueOf(String.valueOf(term)).intValue());
        return t + '|' + n + '|' + (unit == null ? '' : String.valueOf(unit));
    }

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
        if (!found.isEmpty()) {
            // reuse the org's existing policy rather than adding another one
            if (warned.add('proration-reuse')) {
                info('ProrationPolicy: using existing "' + found[0].get('Name') + '" – confirm it prorates daily (BIL-04)');
            }
            return found[0].Id;
        }
        Map<String, SObject> created = sync('ProrationPolicy', new List<String>{ 'Name' }, new List<Map<String, Object>>{
            new Map<String, Object>{ 'Name' => name, 'ProrationPolicyType' => 'StandardTimePeriods',
                'ArePartialPeriodsAllowed' => true, 'StandardTimePeriods' => 'Daily', 'RemainderStrategy' => 'AddToFirst' }
        }, null, null, null, true);
        return created.containsKey(name) ? created.get(name).Id : null;
    }

    /**
     * Points build attributes at attribute definitions the org already has under another spelling
     * (same name in another case, same DeveloperName, or same Code), so they are reused, not duplicated.
     * Returns build name -> org name for the ones renamed.
     */
    Map<String, String> reuseExistingAttributes(List<Map<String, Object>> defs) {
        Map<String, String> renamed = new Map<String, String>();
        if (!hasObject('AttributeDefinition')) {
            return renamed;
        }
        Map<String, Schema.SObjectField> f = fields('AttributeDefinition');
        List<String> cols = new List<String>{ 'Id', 'Name' };
        for (String c : new List<String>{ 'DeveloperName', 'Code' }) {
            if (f.containsKey(c.toLowerCase())) {
                cols.add(c);
            }
        }
        Map<String, String> byAlt = new Map<String, String>();
        Set<String> exactNames = new Set<String>();
        for (SObject r : Database.query('SELECT ' + String.join(cols, ', ') + ' FROM AttributeDefinition LIMIT 5000')) {
            String n = (String) r.get('Name');
            exactNames.add(n);
            byAlt.put('n:' + n.toLowerCase(), n);
            for (String c : cols) {
                if (c != 'Id' && c != 'Name' && r.get(c) != null) {
                    byAlt.put('k:' + String.valueOf(r.get(c)).toLowerCase(), n);
                }
            }
        }
        for (Map<String, Object> d : defs) {
            String n = (String) d.get('Name');
            if (exactNames.contains(n)) {
                continue;
            }
            String hit = byAlt.get('n:' + n.toLowerCase());
            if (hit == null && d.get('DeveloperName') != null) {
                hit = byAlt.get('k:' + String.valueOf(d.get('DeveloperName')).toLowerCase());
            }
            if (hit == null && d.get('Code') != null) {
                hit = byAlt.get('k:' + String.valueOf(d.get('Code')).toLowerCase());
            }
            if (hit != null) {
                info('AttributeDefinition ' + n + ': using existing "' + hit + '"');
                d.put('Name', hit);
                d.remove('DeveloperName');
                renamed.put(n, hit);
            }
        }
        return renamed;
    }

    /** Read-only: lists the ARM setup records the org already has, so the build can reuse them. */
    public void inventory() {
        Map<String, List<String>> objs = new Map<String, List<String>>{
            'ProductSellingModel' => new List<String>{ 'SellingModelType', 'PricingTerm', 'PricingTermUnit', 'Status' },
            'ProrationPolicy' => new List<String>{ 'ProrationPolicyType', 'RemainderStrategy', 'ArePartialPeriodsAllowed' },
            'ProductRelationshipType' => new List<String>{ 'MainProductRoleCat', 'AssociatedProductRoleCat' },
            'ProductCatalog' => new List<String>{ 'Code', 'CatalogType' },
            'ProductClassification' => new List<String>{ 'Code', 'Status' },
            'AttributeDefinition' => new List<String>{ 'DeveloperName', 'Code', 'DataType', 'IsActive' },
            'AttributePicklist' => new List<String>{ 'DataType', 'Status' },
            'AttributeCategory' => new List<String>{ 'Code' },
            'Pricebook2' => new List<String>{ 'IsActive', 'IsStandard' },
            'RateCard' => new List<String>{ 'Type' },
            'UsageResource' => new List<String>{ 'Code', 'Status' },
            'ExpressionSet' => new List<String>{ 'ApiName', 'UsageType', 'ContextDefinitionApiName' },
            'ExpressionSetDefinitionVersion' => new List<String>{ 'DeveloperName', 'Status', 'IsTemplate' },
            'ContextDefinition' => new List<String>{ 'DeveloperName', 'IsActive' },
            'DecisionTable' => new List<String>{ 'DeveloperName', 'Status', 'SourceObject', 'UsageType' },
            'PriceAdjustmentSchedule' => new List<String>{ 'ScheduleType', 'AdjustmentMethodId', 'IsActive', 'CurrencyIsoCode' },
            'AttributeBasedAdjRule' => new List<String>{ 'IsActive' },
            'BundleBasedAdjustment' => new List<String>{ 'AdjustmentType', 'AdjustmentValue' },
            'PricingProcedureResolution' => new List<String>{ 'Priority', 'IsActive' },
            'BillingPolicy' => new List<String>{ 'Status' },
            'BillingTreatment' => new List<String>{ 'Status' },
            'PaymentTerm' => new List<String>{ 'Status' },
            'LegalEntity' => new List<String>{ 'Status' }
        };
        for (String obj : objs.keySet()) {
            if (!hasObject(obj)) {
                log.add('  ' + obj + ': not available');
                continue;
            }
            Map<String, Schema.SObjectField> f = fields(obj);
            String labelField = f.containsKey('name') ? 'Name' : (f.containsKey('masterlabel') ? 'MasterLabel'
                : (f.containsKey('developername') ? 'DeveloperName' : 'Id'));
            List<String> cols = labelField == 'Id' ? new List<String>{ 'Id' } : new List<String>{ 'Id', labelField };
            Integer firstExtra = cols.size();
            for (String c : objs.get(obj)) {
                if (f.containsKey(c.toLowerCase()) && !cols.contains(c)) {
                    cols.add(c);
                }
            }
            List<SObject> rows;
            try {
                rows = Database.query('SELECT ' + String.join(cols, ', ') + ' FROM ' + obj
                    + (f.containsKey('createddate') ? ' ORDER BY CreatedDate' : '') + ' LIMIT 50');
            } catch (Exception e) {
                log.add('  ' + obj + ': could not read – ' + e.getMessage());
                continue;
            }
            log.add('  ' + obj + ': ' + rows.size() + (rows.size() == 50 ? '+' : '') + ' record(s)');
            for (SObject r : rows) {
                List<String> parts = new List<String>();
                for (Integer i = firstExtra; i < cols.size(); i++) {
                    parts.add(cols[i] + '=' + r.get(cols[i]));
                }
                log.add('    - ' + r.get(labelField) + (parts.isEmpty() ? '' : ' (' + String.join(parts, ', ') + ')'));
            }
        }
        // the ProrationPolicy fields this release offers, so daily proration (BIL-04) can be set right
        if (hasObject('ProrationPolicy')) {
            Map<String, Schema.SObjectField> f = fields('ProrationPolicy');
            for (String k : f.keySet()) {
                Schema.DescribeFieldResult d = f.get(k).getDescribe();
                if (!d.isCustom() && d.isCreateable() && d.getType() == Schema.DisplayType.PICKLIST) {
                    List<String> vals = new List<String>();
                    for (Schema.PicklistEntry e : d.getPicklistValues()) {
                        vals.add(e.getValue());
                    }
                    log.add('  ProrationPolicy.' + d.getName() + ' values: ' + String.join(vals, ', '));
                }
            }
        }
        Integer products = Database.countQuery('SELECT COUNT() FROM Product2');
        log.add('  Product2: ' + products + ' product(s) in the org');
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
        // Demo records are intentionally alike (six Halo spas in one city): save past duplicate-rule ALERTS.
        // Duplicate rules set to BLOCK still block.
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.OptAllOrNone = false;
        dml.DuplicateRuleHeader.AllowSave = true;
        List<Database.SaveResult> ins = Database.insert(toInsert, dml);
        for (Integer i = 0; i < ins.size(); i++) {
            if (ins[i].isSuccess()) {
                result.put(insertKeys[i], toInsert[i]);
                ok++;
            } else {
                bad++;
                fail(obj + ' [' + insertKeys[i].replace('|', ' / ') + '] insert failed: ' + messages(ins[i].getErrors()));
            }
        }
        Integer upd = 0;
        List<Database.SaveResult> ups = Database.update(toUpdate, dml);
        for (Integer i = 0; i < ups.size(); i++) {
            if (ups[i].isSuccess()) {
                upd++;
            } else {
                bad++;
                fail(obj + ' [' + updateKeys[i].replace('|', ' / ') + '] update failed: ' + messages(ups[i].getErrors()));
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
        if (v instanceof Decimal || v instanceof Integer || v instanceof Double || v instanceof Long) {
            // 1, 1.0 and 1.00 are the same key
            return Decimal.valueOf(String.valueOf(v)).stripTrailingZeros().toPlainString();
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

    static Map<String, Object> address(Id parentId, String addressType, String name, Map<String, Object> a) {
        return new Map<String, Object>{ 'ParentId' => parentId, 'AddressType' => addressType, 'Name' => name,
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
            // keep multi-line trigger errors on one line so the whole cause reaches the log
            m.add(e.getStatusCode() + ': ' + e.getMessage().replaceAll('[\\r\\n]+', ' | ') + (e.getFields().isEmpty() ? '' : ' ' + e.getFields()));
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
        log.add('  ERROR ' + m.replaceAll('[\\r\\n]+', ' | '));
    }
}
