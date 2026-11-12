// Read-only: product qualification setup (procedures, decision tables, records, country in context)
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
for (String o : new List<String>{ 'ProductQualification', 'ProductDisqualification', 'ProductCategoryQualification', 'ProductCategoryDisqual' }) {
    if (!gd.containsKey(o.toLowerCase())) { System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ': not available'); continue; }
    Schema.DescribeSObjectResult d = gd.get(o.toLowerCase()).getDescribe();
    List<String> fs = new List<String>();
    for (Schema.SObjectField sf : d.fields.getMap().values()) {
        Schema.DescribeFieldResult x = sf.getDescribe();
        fs.add(x.getName() + ':' + x.getType() + (x.isNillable() ? '' : '!') + (x.isCreateable() ? '' : '(ro)') + (x.isCustom() ? '(custom)' : '') + (x.getDefaultValue() != null ? '=' + x.getDefaultValue() : ''));
    }
    fs.sort();
    System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ' create=' + d.isCreateable() + ' rows=' + Database.countQuery('SELECT COUNT() FROM ' + o) + ' | ' + String.join(fs, ', '));
    for (SObject r : Database.query('SELECT FIELDS(STANDARD) FROM ' + o + ' LIMIT 3')) System.debug(LoggingLevel.ERROR, '  ROW ' + r);
}
for (SObject es : Database.query('SELECT Id, Name, ApiName, UsageType, InterfaceSourceType FROM ExpressionSet')) {
    System.debug(LoggingLevel.ERROR, 'PROCEDURE ' + es.get('UsageType') + ' | ' + es.get('Name') + ' (' + es.get('ApiName') + ')');
}
for (Account a : Database.query('SELECT Name, MB_Region__c, BillingCountry, ShippingCountry, CurrencyIsoCode FROM Account WHERE Name LIKE \'Pulse%\' OR Name LIKE \'Kraftwerk%\' OR Name LIKE \'Sunrise%\' OR Name LIKE \'Reformer Lab Pty%\'')) {
    System.debug(LoggingLevel.ERROR, 'ACCOUNT ' + a.Name + ' | region=' + a.get('MB_Region__c') + ' | billing=' + a.BillingCountry + ' | shipping=' + a.ShippingCountry + ' | ' + a.get('CurrencyIsoCode'));
}
for (SObject q : Database.query('SELECT Product.ProductCode, MB_Region__c, EffectiveFromDate, EffectiveToDate, ParentProductId, RootProductId FROM ProductQualification')) {
    System.debug(LoggingLevel.ERROR, 'PQ ' + q.getSObject('Product').get('ProductCode') + ' | ' + q.get('MB_Region__c') + ' | ' + q.get('EffectiveFromDate') + '..' + q.get('EffectiveToDate'));
}
