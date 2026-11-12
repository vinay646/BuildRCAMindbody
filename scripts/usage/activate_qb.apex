// Usage test, step 1: activate QuantumBit Database, its usage products, price book entries and rate card entries
Set<Id> ids = new Set<Id>();
for (Product2 p : [SELECT Id FROM Product2 WHERE ProductCode = 'QB-DB']) ids.add(p.Id);
for (ProductUsageResource r : [SELECT UsageResource.UsageDefinitionProductId FROM ProductUsageResource WHERE Product.ProductCode = 'QB-DB']) ids.add(r.UsageResource.UsageDefinitionProductId);
List<Product2> ps = [SELECT Id, ProductCode, IsActive FROM Product2 WHERE Id IN :ids];
for (Product2 p : ps) p.IsActive = true;
update ps;
List<PricebookEntry> pbes = [SELECT Id, IsActive FROM PricebookEntry WHERE Product2Id IN :ids];
for (PricebookEntry e : pbes) e.IsActive = true;
update pbes;
List<SObject> rces = Database.query('SELECT Id, Status, RateCard.Name, UsageResource.Name FROM RateCardEntry WHERE ProductId IN :ids');
for (SObject r : rces) System.debug(LoggingLevel.ERROR, 'RCE ' + r.getSObject('RateCard').get('Name') + ' | ' + r.getSObject('UsageResource').get('Name') + ' | ' + r.get('Status'));
for (Product2 p : [SELECT ProductCode, IsActive FROM Product2 WHERE Id IN :ids]) System.debug(LoggingLevel.ERROR, 'ACTIVE ' + p.ProductCode + ' ' + p.IsActive);
System.debug(LoggingLevel.ERROR, 'PBE activated: ' + pbes.size());
// why earlier usage summary jobs failed
List<String> fs = new List<String>(Schema.getGlobalDescribe().get('batchjobpart').getDescribe().fields.getMap().keySet());
for (SObject r : Database.query('SELECT ' + String.join(fs, ',') + ' FROM BatchJobPart WHERE Status = \'Failed\' ORDER BY CreatedDate DESC LIMIT 2')) {
    Map<String, Object> m = r.getPopulatedFieldsAsMap();
    System.debug(LoggingLevel.ERROR, 'FAILEDPART ' + JSON.serialize(m));
}
