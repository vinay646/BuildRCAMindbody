// CHANGES QA: Marketplace per requirement. MB_MKT_FIRST counts first purchases (unit First Purchase Event, $0);
// new MB_MKT_FEE carries the fee (20% of the purchase, capped at 30, worked out by flow MB_Marketplace_Fee) at $1 per fee unit. Idempotent.
String log = '';
SObject cl(String obj, Id srcId, Map<String, Object> ov) {
  List<String> f = new List<String>();
  for (Schema.SObjectField x : Schema.getGlobalDescribe().get(obj).getDescribe().fields.getMap().values()) { Schema.DescribeFieldResult d = x.getDescribe(); if (d.isCreateable()) f.add(d.getName()); }
  SObject s = Database.query('SELECT ' + String.join(f, ',') + ' FROM ' + obj + ' WHERE Id = :srcId')[0].clone(false, true);
  for (String k : ov.keySet()) try { s.put(k, ov.get(k)); } catch (Exception e) { log += 'skip ' + obj + '.' + k + '; '; }
  return s;
}
void setStatus(Id id, String st) { SObject u = id.getSObjectType().newSObject(id); u.put('Status', st); update u; }
Id evm = [SELECT Id FROM ProductSellingModel WHERE Name = 'Evergreen Monthly' LIMIT 1].Id;
Id prod = [SELECT Id FROM Product2 WHERE ProductCode = 'MB-MKT' LIMIT 1].Id;
Id fpUom = [SELECT Id FROM UnitOfMeasure WHERE UnitCode = 'MB_FIRST_PURCHASE' LIMIT 1].Id;
Id feeUom = [SELECT Id FROM UnitOfMeasure WHERE UnitCode = 'MB_MKT_FEE_USD' LIMIT 1].Id;
UsageResource first = [SELECT Id, DefaultUnitOfMeasureId FROM UsageResource WHERE Code = 'MB_MKT_FIRST'];
// 1 count resource back to First Purchase Event
if (first.DefaultUnitOfMeasureId != fpUom) {
  try { update new UsageResource(Id = first.Id, DefaultUnitOfMeasureId = fpUom); log += 'first unit reset; '; }
  catch (Exception e) { try { setStatus(first.Id, 'Draft'); update new UsageResource(Id = first.Id, DefaultUnitOfMeasureId = fpUom); setStatus(first.Id, 'Active'); log += 'first unit reset (draft); '; } catch (Exception e2) { log += 'first unit ERR ' + e2.getMessage().left(150) + '; '; } }
}
// 2 fee resource
List<UsageResource> fl = [SELECT Id FROM UsageResource WHERE Code = 'MB_MKT_FEE'];
Id feeRes;
if (fl.isEmpty()) {
  try { SObject r = cl('UsageResource', first.Id, new Map<String, Object>{ 'Name' => 'Marketplace New-Client Fee', 'Code' => 'MB_MKT_FEE', 'DefaultUnitOfMeasureId' => feeUom, 'Status' => 'Draft' }); insert r; feeRes = r.Id; setStatus(feeRes, 'Active'); log += 'fee resource ok; '; }
  catch (Exception e) { log += 'fee resource ERR ' + e.getMessage().left(200) + '; '; }
} else feeRes = fl[0].Id;
// 3 product usage resource + policy
ProductUsageResource pur0 = [SELECT Id FROM ProductUsageResource WHERE ProductId = :prod AND UsageResource.Code = 'MB_MKT_FIRST' LIMIT 1];
if (feeRes != null && [SELECT COUNT() FROM ProductUsageResource WHERE ProductId = :prod AND UsageResourceId = :feeRes] == 0) {
  try {
    SObject p = cl('ProductUsageResource', pur0.Id, new Map<String, Object>{ 'UsageResourceId' => feeRes, 'Status' => 'Draft' }); insert p; log += 'fee PUR ok; ';
    List<ProductUsageResourcePolicy> pol = [SELECT Id FROM ProductUsageResourcePolicy WHERE ProductUsageResourceId = :pur0.Id LIMIT 1];
    if (!pol.isEmpty()) { insert cl('ProductUsageResourcePolicy', pol[0].Id, new Map<String, Object>{ 'ProductUsageResourceId' => p.Id }); log += 'fee policy ok; '; }
    setStatus(p.Id, 'Active'); log += 'fee PUR active; ';
  } catch (Exception e) { log += 'fee PUR ERR ' + e.getMessage().left(200) + '; '; }
}
// 4 rates: count $0 (First Purchase Event), fee $1 (fee unit); retire the old $1-per-fee entry on the count resource
RateCardEntry old = [SELECT Id, RateCardId, Status, DefaultUnitOfMeasureId FROM RateCardEntry WHERE ProductId = :prod AND UsageResourceId = :first.Id AND RateCardType = 'Base' ORDER BY CreatedDate LIMIT 1];
Map<Id, List<Object>> want = new Map<Id, List<Object>>{ first.Id => new List<Object>{ fpUom, 0.0 } };
if (feeRes != null) want.put(feeRes, new List<Object>{ feeUom, 1.0 });
for (Id rid : want.keySet()) {
  Id uom = (Id) want.get(rid)[0];
  if ([SELECT COUNT() FROM RateCardEntry WHERE RateCardId = :old.RateCardId AND UsageResourceId = :rid AND DefaultUnitOfMeasureId = :uom AND Status = 'Active'] == 0) {
    try { SObject e = cl('RateCardEntry', old.Id, new Map<String, Object>{ 'UsageResourceId' => rid, 'DefaultUnitOfMeasureId' => uom, 'Rate' => want.get(rid)[1], 'ProductSellingModelId' => evm, 'Status' => 'Draft' }); insert e; setStatus(e.Id, 'Active'); log += 'rate ' + want.get(rid)[1] + ' ok; '; }
    catch (Exception ex) { log += 'rate ERR ' + ex.getMessage().left(200) + '; '; }
  }
}
if (old.DefaultUnitOfMeasureId == feeUom && old.Status == 'Active') { try { setStatus(old.Id, 'Inactive'); log += 'old rate inactive; '; } catch (Exception e) { log += 'old rate ERR ' + e.getMessage().left(150) + '; '; } }
System.debug(LoggingLevel.ERROR, 'QAU ' + log);
