// Probe (changes nothing: every insert is rolled back).
// Finding so far: ProductConfigurationRule cannot be created by API (createable=false, Name not editable) -
// the builder creates it inside a Rule Library with UsageType 'Configurator'. The org has only the DRO library,
// which is why the builder fails with "reading 'RuleLibraryVersions'". This lists the library definitions and
// tries a Configurator library + version (rolled back).
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
String allFields(String o) {
    List<String> f = new List<String>();
    for (Schema.SObjectField sf : Schema.getGlobalDescribe().get(o.toLowerCase()).getDescribe().fields.getMap().values()) {
        Schema.DescribeFieldResult d = sf.getDescribe();
        if (d.getType() == Schema.DisplayType.BASE64 || d.getType() == Schema.DisplayType.TEXTAREA && d.getLength() > 4000) continue;
        f.add(d.getName());
    }
    return String.join(f, ', ');
}
for (String o : new List<String>{ 'RuleLibraryDefinition', 'RuleLibraryDefVersion', 'RuleLibrary', 'RuleLibraryVersion' }) {
    if (!gd.containsKey(o.toLowerCase())) { System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ': not available'); continue; }
    try {
        List<SObject> rows = Database.query('SELECT ' + allFields(o) + ' FROM ' + o + ' LIMIT 50');
        System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ' rows=' + rows.size());
        for (SObject r : rows) {
            Map<String, Object> m = r.getPopulatedFieldsAsMap().clone();
            for (String k : new List<String>{ 'CreatedById', 'LastModifiedById', 'SystemModstamp', 'CreatedDate', 'LastModifiedDate', 'IsDeleted', 'CurrencyIsoCode', 'LastViewedDate', 'LastReferencedDate', 'OwnerId' }) m.remove(k);
            System.debug(LoggingLevel.ERROR, '  ROW ' + o + ' ' + JSON.serialize(m));
        }
    } catch (Exception ex) { System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ' query failed: ' + ex.getMessage()); }
}
// Trial: Configurator library + version for each definition / def version found (rolled back)
List<SObject> defs = Database.query('SELECT Id, DeveloperName FROM RuleLibraryDefinition');
List<SObject> defVers = Database.query('SELECT ' + allFields('RuleLibraryDefVersion') + ' FROM RuleLibraryDefVersion');
for (SObject def : defs) {
    Savepoint sp = Database.setSavepoint();
    String tag = 'def ' + def.get('DeveloperName');
    try {
        SObject lib = gd.get('rulelibrary').newSObject();
        lib.put('Name', 'Mindbody Product Rules'); lib.put('ApiName', 'Mindbody_Product_Rules');
        lib.put('UsageType', 'Configurator'); lib.put('RuleLibraryDefinitionId', def.Id);
        lib.put('ContextDefinitionName', 'RLM_SalesTransactionContext');
        Database.SaveResult r1 = Database.insert(lib, false);
        if (!r1.isSuccess()) { System.debug(LoggingLevel.ERROR, 'TRY LIB FAIL ' + tag + ': ' + r1.getErrors()[0].getStatusCode() + ' ' + r1.getErrors()[0].getMessage()); }
        else {
            System.debug(LoggingLevel.ERROR, 'TRY LIB OK ' + tag);
            for (SObject dv : defVers) {
                Map<String, Object> dm = dv.getPopulatedFieldsAsMap();
                if (!dm.values().contains(def.Id) && !String.valueOf(dm).contains(String.valueOf(def.Id))) continue;
                Savepoint sp2 = Database.setSavepoint();
                SObject ver = gd.get('rulelibraryversion').newSObject();
                ver.put('Name', 'Mindbody Product Rules V1'); ver.put('ApiName', 'Mindbody_Product_Rules_V1');
                ver.put('RuleLibraryId', lib.Id); ver.put('Description', 'Mindbody configuration rules');
                ver.put('RuleLibraryDefVersionId', dv.Id); ver.put('StartDateTime', DateTime.now());
                ver.put('Status', 'Draft'); ver.put('VersionNumber', 1);
                ver.put('ContextDefinitionName', 'RLM_SalesTransactionContext');
                Database.SaveResult r2 = Database.insert(ver, false);
                System.debug(LoggingLevel.ERROR, (r2.isSuccess() ? 'TRY VER OK ' : 'TRY VER FAIL ') + tag + ' defVer ' + dv.Id
                    + (r2.isSuccess() ? '' : ': ' + r2.getErrors()[0].getStatusCode() + ' ' + r2.getErrors()[0].getMessage()));
                if (r2.isSuccess()) {
                    ver.put('Status', 'Active');
                    Database.SaveResult r3 = Database.update(ver, false);
                    System.debug(LoggingLevel.ERROR, (r3.isSuccess() ? 'TRY ACTIVATE OK ' : 'TRY ACTIVATE FAIL ') + tag
                        + (r3.isSuccess() ? '' : ': ' + r3.getErrors()[0].getMessage()));
                }
                Database.rollback(sp2);
            }
        }
    } catch (Exception ex) { System.debug(LoggingLevel.ERROR, 'TRY EXCEPTION ' + tag + ': ' + ex.getMessage()); }
    Database.rollback(sp);
}
