// Probe (changes nothing: every insert is rolled back): what Product Configuration Rules and Rule Libraries need.
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
for (String o : new List<String>{ 'ProductConfigurationRule', 'RuleLibrary', 'RuleLibraryVersion', 'RuleLibraryDefinition' }) {
    if (!gd.containsKey(o.toLowerCase())) { System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ': not available'); continue; }
    Schema.DescribeSObjectResult od = gd.get(o.toLowerCase()).getDescribe();
    System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ' createable=' + od.isCreateable());
    for (Schema.SObjectField sf : od.fields.getMap().values()) {
        Schema.DescribeFieldResult d = sf.getDescribe();
        if (!d.isCreateable() || d.isCustom()) continue;
        String info = d.getName() + ' ' + d.getType() + (d.isNillable() ? '' : ' REQUIRED') + (d.isDefaultedOnCreate() ? ' (defaulted)' : '')
            + (d.getLength() > 0 ? ' len ' + d.getLength() : '');
        if (d.getType() == Schema.DisplayType.PICKLIST) {
            List<String> v = new List<String>();
            for (Schema.PicklistEntry e : d.getPicklistValues()) v.add(e.getValue());
            info += ' [' + String.join(v, '|') + ']';
        } else if (d.getType() == Schema.DisplayType.REFERENCE) {
            info += ' -> ' + d.getReferenceTo();
        }
        System.debug(LoggingLevel.ERROR, '  FIELD ' + o + '.' + info);
    }
}
Id mbUlt = null; Id mbAic = null;
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN ('MB-ULT', 'MB-AIC')]) {
    if (p.ProductCode == 'MB-ULT') mbUlt = p.Id; else mbAic = p.Id;
}
System.debug(LoggingLevel.ERROR, 'PRODUCTS MB-ULT=' + mbUlt + ' MB-AIC=' + mbAic);
// Test inserts, each rolled back
List<Map<String, Object>> tries = new List<Map<String, Object>>{
    new Map<String, Object>{ 'Name' => 'CR-05 AI Concierge included in Ultimate', 'ApiName' => 'CR_05_AI_Concierge_included_in_Ultimate',
        'RuleType' => 'Configurator', 'RuleSubType' => 'BundleProduct', 'ProcessScope' => 'Bundle', 'Status' => 'Draft', 'Sequence' => 5 },
    new Map<String, Object>{ 'Name' => 'Probe minimal', 'ApiName' => 'Probe_minimal', 'RuleType' => 'Configurator' }
};
for (Map<String, Object> t : tries) {
    Savepoint sp = Database.setSavepoint();
    try {
        SObject r = gd.get('productconfigurationrule').newSObject();
        for (String k : t.keySet()) r.put(k, t.get(k));
        Database.SaveResult res = Database.insert(r, false);
        if (res.isSuccess()) {
            System.debug(LoggingLevel.ERROR, 'TRY OK ' + t.get('Name') + ' -> inserted (rolled back)');
        } else {
            for (Database.Error e : res.getErrors()) {
                System.debug(LoggingLevel.ERROR, 'TRY FAIL ' + t.get('Name') + ': ' + e.getStatusCode() + ' ' + e.getMessage() + ' ' + e.getFields());
            }
        }
    } catch (Exception ex) {
        System.debug(LoggingLevel.ERROR, 'TRY EXCEPTION ' + t.get('Name') + ': ' + ex.getMessage());
    }
    Database.rollback(sp);
}
