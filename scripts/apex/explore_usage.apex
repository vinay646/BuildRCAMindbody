// Read-only: QuantumBit Database usage setup and the usage records an earlier activation created
Set<Id> ids = new Set<Id>();
for (Product2 p : [SELECT Id, ProductCode, Name, IsActive, UsageModelType, Type, ConfigureDuringSale FROM Product2 WHERE ProductCode IN ('QB-DB') OR Id IN (SELECT UsageDefinitionProductId FROM UsageResource)]) {
    ids.add(p.Id);
    System.debug(LoggingLevel.ERROR, 'PROD ' + p.Id + ' | ' + p.ProductCode + ' | ' + p.Name + ' | active=' + p.IsActive + ' | ' + p.UsageModelType + ' | ' + p.Type);
}
for (ProductSellingModelOption o : [SELECT Product2.ProductCode, ProductSellingModel.Name, ProductSellingModel.Status, ProductSellingModelId FROM ProductSellingModelOption WHERE Product2Id IN :ids]) {
    System.debug(LoggingLevel.ERROR, 'PSMO ' + o.Product2.ProductCode + ' | ' + o.ProductSellingModel.Name + ' ' + o.ProductSellingModelId + ' | ' + o.ProductSellingModel.Status);
}
for (PricebookEntry e : [SELECT Product2.ProductCode, Pricebook2.Name, Pricebook2Id, Pricebook2.IsActive, IsActive, UnitPrice, CurrencyIsoCode, ProductSellingModel.Name FROM PricebookEntry WHERE Product2Id IN :ids]) {
    System.debug(LoggingLevel.ERROR, 'PBE ' + e.Product2.ProductCode + ' | ' + e.Pricebook2.Name + ' ' + e.Pricebook2Id + ' active=' + e.Pricebook2.IsActive + ' | entry active=' + e.IsActive + ' | ' + e.UnitPrice + ' ' + e.CurrencyIsoCode + ' | ' + e.ProductSellingModel.Name);
}
for (ProductUsageResource r : [SELECT Product.ProductCode, UsageResource.Name, UsageResource.Status, Status FROM ProductUsageResource WHERE Product.ProductCode = 'QB-DB']) {
    System.debug(LoggingLevel.ERROR, 'PUR ' + r.UsageResource.Name + ' | ' + r.Status + ' | resource ' + r.UsageResource.Status);
}
for (String o : new List<String>{ 'UsageEntitlementAccount', 'UsageEntitlementBucket', 'TransactionUsageEntitlement', 'AssetRateCardEntry', 'TransactionJournal', 'UsagePrdGrantBindingPolicy', 'ProductUsageGrant' }) {
    for (SObject r : Database.query('SELECT FIELDS(STANDARD) FROM ' + o + ' LIMIT 4')) System.debug(LoggingLevel.ERROR, 'ROW ' + o + ' ' + r);
}
for (Order o : [SELECT Id, OrderNumber, Status, Account.Name, CreatedDate FROM Order WHERE Id IN (SELECT OrderId FROM OrderItem WHERE Product2.ProductCode LIKE 'QB-%') ORDER BY CreatedDate DESC LIMIT 5]) {
    System.debug(LoggingLevel.ERROR, 'ORDER ' + o.OrderNumber + ' | ' + o.Status + ' | ' + o.Account.Name + ' | ' + o.CreatedDate);
}
