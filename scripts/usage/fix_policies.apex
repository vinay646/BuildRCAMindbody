// Usage test: give QuantumBit Database the usage resource policies it lacks, and fill empty binding policies
SObject ref = Database.query('SELECT RatingFrequencyPolicyId, UsageOveragePolicyId FROM ProductUsageResourcePolicy WHERE ProductUsageResource.Product.ProductCode = \'CS-25Gb\' LIMIT 1')[0];
Id rating = (Id) ref.get('RatingFrequencyPolicyId'), overage = (Id) ref.get('UsageOveragePolicyId');
Id monthlyTotal = [SELECT Id FROM UsageResourceBillingPolicy WHERE Code = 'monthlytotal' LIMIT 1].Id;
Id termAnnual = [SELECT ProductSellingModelId FROM ProductSellingModelOption WHERE Product2.ProductCode = 'QB-DB' LIMIT 1].ProductSellingModelId;
List<SObject> pols = new List<SObject>();
for (ProductUsageResource r : [SELECT Id, UsageResource.Name FROM ProductUsageResource WHERE Product.ProductCode = 'QB-DB' AND Id NOT IN (SELECT ProductUsageResourceId FROM ProductUsageResourcePolicy)]) {
    SObject p = Schema.getGlobalDescribe().get('ProductUsageResourcePolicy').newSObject();
    p.put('ProductUsageResourceId', r.Id); p.put('ProductSellingModelId', termAnnual);
    p.put('UsageAggregationPolicyId', monthlyTotal); p.put('RatingFrequencyPolicyId', rating); p.put('UsageOveragePolicyId', overage);
    pols.add(p);
    System.debug(LoggingLevel.ERROR, 'POLICY for QB-DB / ' + r.UsageResource.Name);
}
for (Database.SaveResult s : Database.insert(pols, false)) System.debug(LoggingLevel.ERROR, 'INSERT ' + (s.isSuccess() ? 'ok ' + s.getId() : s.getErrors()[0].getMessage()));
List<SObject> binds = Database.query('SELECT Id, BindingObjectId, UsageResource.Name FROM BindingObjUsageRsrcPlcy WHERE UsageAggregationPolicyId = null');
for (SObject b : binds) { b.put('UsageAggregationPolicyId', monthlyTotal); b.put('RatingFrequencyPolicyId', rating); b.put('UsageOveragePolicyId', overage); }
for (Database.SaveResult s : Database.update(binds, false)) System.debug(LoggingLevel.ERROR, 'BINDING ' + (s.isSuccess() ? 'ok ' + s.getId() : s.getErrors()[0].getMessage()));
