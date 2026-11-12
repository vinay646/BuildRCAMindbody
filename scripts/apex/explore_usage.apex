// Read-only: usage management setup in the org (which products are usage-enabled, rate cards, summaries)
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
List<String> objs = new List<String>{ 'UsageResource', 'ProductUsageResource', 'ProductUsageGrant', 'UsageResourceBillingPolicy', 'UsagePrdGrantBindingPolicy',
    'RateCard', 'RateCardEntry', 'PriceBookRateCard', 'UsageSummary', 'UsageEntitlementAccount', 'UsageEntitlementBucket', 'AssetRateCardEntry', 'TransactionUsageEntitlement',
    'UsageRatableSummary', 'UsageBillingPeriodItem', 'TransactionJournal', 'UsageType', 'UnitOfMeasure', 'UnitOfMeasureClass', 'UsageCommitmentPolicy', 'UsageGrantRenewalPolicy',
    'UsageGrantRolloverPolicy', 'UsageOveragePolicy', 'ProductUsageResourcePolicy', 'UsageResourcePolicy', 'RatingRequestBatchJob', 'BindingObjectRateAdjustment', 'BindingObjUsageRsrcPlcy' };
for (String o : objs) {
    if (!gd.containsKey(o.toLowerCase())) { System.debug(LoggingLevel.ERROR, 'OBJ ' + o + ': n/a'); continue; }
    Integer n = 0;
    try { n = Database.countQuery('SELECT COUNT() FROM ' + o); } catch (Exception e) { System.debug(LoggingLevel.ERROR, 'OBJ ' + o + ': ' + e.getMessage()); continue; }
    List<String> fs = new List<String>();
    for (Schema.SObjectField f : gd.get(o.toLowerCase()).getDescribe().fields.getMap().values()) {
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.isCreateable() && !d.isNillable() && !d.isDefaultedOnCreate()) fs.add(d.getName() + '!');
        else if (d.isCreateable() && (d.getType() == Schema.DisplayType.REFERENCE || d.getType() == Schema.DisplayType.PICKLIST)) fs.add(d.getName());
    }
    fs.sort();
    System.debug(LoggingLevel.ERROR, 'OBJ ' + o + ' rows=' + n + ' | ' + String.join(fs, ', '));
}
// usage-enabled products and a sample of each record
if (gd.containsKey('productusageresource')) {
    for (SObject r : Database.query('SELECT Product.ProductCode, Product.Name, UsageResource.Name FROM ProductUsageResource LIMIT 15')) {
        System.debug(LoggingLevel.ERROR, 'PUR ' + r.getSObject('Product').get('ProductCode') + ' ' + r.getSObject('Product').get('Name') + ' -> ' + r.getSObject('UsageResource').get('Name'));
    }
}
for (String o : new List<String>{ 'UsageResource', 'RateCard', 'RateCardEntry', 'UsageSummary', 'UsageResourceBillingPolicy', 'PriceBookRateCard' }) {
    if (!gd.containsKey(o.toLowerCase())) continue;
    try { for (SObject r : Database.query('SELECT FIELDS(STANDARD) FROM ' + o + ' LIMIT 3')) System.debug(LoggingLevel.ERROR, 'ROW ' + o + ' ' + r); } catch (Exception e) { System.debug(LoggingLevel.ERROR, 'ROW ' + o + ' ' + e.getMessage()); }
}
for (Product2 p : [SELECT ProductCode, Name, Type, UsageModelType FROM Product2 WHERE UsageModelType != null LIMIT 15]) {
    System.debug(LoggingLevel.ERROR, 'USAGEPROD ' + p.ProductCode + ' | ' + p.Name + ' | ' + p.Type + ' | ' + p.UsageModelType);
}
