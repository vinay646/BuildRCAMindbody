// Read-only: full usage setup of one product (code in the first line), checked against docs/USAGE_PRODUCT_SETUP.md
String code = 'CS-25Gb';
String o2s(SObject r) { Map<String, Object> m = r.getPopulatedFieldsAsMap().clone(); for (String k : new List<String>(m.keySet())) if (k.startsWith('Created') || k.startsWith('LastModified') || k == 'SystemModstamp' || k == 'IsDeleted' || k == 'OwnerId' || k.startsWith('LastViewed') || k.startsWith('LastReferenced')) m.remove(k); return JSON.serialize(m); }
List<SObject> all(String obj, String whereClause) {
    List<String> fs = new List<String>(Schema.getGlobalDescribe().get(obj.toLowerCase()).getDescribe().fields.getMap().keySet());
    return Database.query('SELECT ' + String.join(fs, ',') + ' FROM ' + obj + ' WHERE ' + whereClause);
}
Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = :code LIMIT 1];
Id pid = p.Id;
for (SObject r : all('Product2', 'Id = :pid')) System.debug(LoggingLevel.ERROR, 'PRODUCT ' + o2s(r));
for (SObject r : all('ProductSellingModelOption', 'Product2Id = :pid')) System.debug(LoggingLevel.ERROR, 'PSMO ' + o2s(r));
for (SObject r : all('PricebookEntry', 'Product2Id = :pid')) System.debug(LoggingLevel.ERROR, 'PBE ' + o2s(r));
List<SObject> purs = all('ProductUsageResource', 'ProductId = :pid');
Set<Id> purIds = new Set<Id>(), urIds = new Set<Id>();
for (SObject r : purs) { purIds.add(r.Id); urIds.add((Id) r.get('UsageResourceId')); System.debug(LoggingLevel.ERROR, 'PUR ' + o2s(r)); }
for (SObject r : all('UsageResource', 'Id IN :urIds')) System.debug(LoggingLevel.ERROR, 'RESOURCE ' + o2s(r));
List<SObject> purps = all('ProductUsageResourcePolicy', 'ProductUsageResourceId IN :purIds');
Set<Id> polIds = new Set<Id>();
for (SObject r : purps) { System.debug(LoggingLevel.ERROR, 'PUR_POLICY ' + o2s(r)); for (String f : new List<String>{ 'UsageAggregationPolicyId', 'RatingFrequencyPolicyId', 'UsageOveragePolicyId', 'UsageCommitmentPolicyId' }) if (r.get(f) != null) polIds.add((Id) r.get(f)); }
for (String obj : new List<String>{ 'UsageResourceBillingPolicy', 'RatingFrequencyPolicy', 'UsageOveragePolicy' }) for (SObject r : all(obj, 'Id IN :polIds')) System.debug(LoggingLevel.ERROR, 'POLICY ' + obj + ' ' + o2s(r));
for (SObject r : all('ProductUsageGrant', 'ProductUsageResourceId IN :purIds')) System.debug(LoggingLevel.ERROR, 'GRANT ' + o2s(r));
for (SObject r : all('UsagePrdGrantBindingPolicy', 'Product2Id = :pid')) System.debug(LoggingLevel.ERROR, 'BINDING_POLICY ' + o2s(r));
List<SObject> rces = all('RateCardEntry', 'ProductId = :pid');
Set<Id> rcIds = new Set<Id>();
for (SObject r : rces) { rcIds.add((Id) r.get('RateCardId')); System.debug(LoggingLevel.ERROR, 'RATE_ENTRY ' + o2s(r)); }
for (SObject r : all('RateCard', 'Id IN :rcIds')) System.debug(LoggingLevel.ERROR, 'RATE_CARD ' + o2s(r));
for (SObject r : all('PriceBookRateCard', 'RateCardId IN :rcIds')) System.debug(LoggingLevel.ERROR, 'PB_RATE_CARD ' + o2s(r));
Set<Id> rceIds = new Map<Id, SObject>(rces).keySet();
if (Schema.getGlobalDescribe().containsKey('ratecardentry') && !rceIds.isEmpty()) {
    for (String obj : new List<String>{ 'RateAdjustmentByTier' }) {
        if (Schema.getGlobalDescribe().containsKey(obj.toLowerCase())) for (SObject r : all(obj, 'RateCardEntryId IN :rceIds')) System.debug(LoggingLevel.ERROR, 'TIER ' + o2s(r));
    }
}
for (SObject r : all('BindingObjUsageRsrcPlcy', 'BindingObjectId IN (SELECT Id FROM Asset WHERE Product2Id = :pid)')) System.debug(LoggingLevel.ERROR, 'ASSET_BINDING ' + o2s(r));
