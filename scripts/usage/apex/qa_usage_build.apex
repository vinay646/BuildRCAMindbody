// CHANGES QA usage set-up: activates the SMS rate; Marketplace unit = fee dollars; policies for MB-MKT and MB-PAY; grant binding policies; Marketplace $1 and Payments $0.30 rates; links the rate card to the price books. Idempotent.
String log = '';
SObject cl(String obj, Id srcId, Map<String, Object> ov) {
  List<String> f = new List<String>();
  for (Schema.SObjectField x : Schema.getGlobalDescribe().get(obj).getDescribe().fields.getMap().values()) { Schema.DescribeFieldResult d = x.getDescribe(); if (d.isCreateable()) f.add(d.getName()); }
  SObject s = Database.query('SELECT ' + String.join(f, ',') + ' FROM ' + obj + ' WHERE Id = :srcId')[0].clone(false, true);
  for (String k : ov.keySet()) try { s.put(k, ov.get(k)); } catch (Exception e) { log += 'skip ' + obj + '.' + k + '; '; }
  return s;
}
void setStatus(SObject r, String st) { SObject u = r.getSObjectType().newSObject((Id) r.get('Id')); u.put('Status', st); update u; }
Id evm = [SELECT Id FROM ProductSellingModel WHERE Name = 'Evergreen Monthly' LIMIT 1].Id;
Id monthly = [SELECT Id FROM UsageResourceBillingPolicy WHERE Name = 'Monthly Total' LIMIT 1].Id;
Map<String, Product2> prod = new Map<String, Product2>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN ('MB-SMS','MB-MKT','MB-PAY')]) prod.put(p.ProductCode, p);
Map<String, UsageResource> res = new Map<String, UsageResource>();
for (UsageResource r : [SELECT Id, Code, Status, UnitOfMeasureClassId, DefaultUnitOfMeasureId FROM UsageResource WHERE Code IN ('MB_SMS_MSG','MB_MKT_FIRST','MB_PAY_TXN')]) res.put(r.Code, r);
// 1 SMS base rate active
RateCardEntry smsRce = [SELECT Id, Status, RateCardId FROM RateCardEntry WHERE UsageResource.Code = 'MB_SMS_MSG' AND RateCardType = 'Base' LIMIT 1];
if (smsRce.Status != 'Active') { try { setStatus(smsRce, 'Active'); log += 'SMS rate active; '; } catch (Exception e) { log += 'SMS rate ERR ' + e.getMessage().left(150) + '; '; } }
// 2 Marketplace unit = fee dollars
UsageResource mkt = res.get('MB_MKT_FIRST');
List<UnitOfMeasure> fee = [SELECT Id, Status FROM UnitOfMeasure WHERE UnitCode = 'MB_MKT_FEE_USD'];
Id feeUom;
if (fee.isEmpty()) {
  try { SObject u = cl('UnitOfMeasure', mkt.DefaultUnitOfMeasureId, new Map<String, Object>{ 'Name' => 'Marketplace Fee (USD)', 'UnitCode' => 'MB_MKT_FEE_USD', 'Status' => 'Draft' }); insert u; feeUom = u.Id; setStatus(u, 'Active'); log += 'fee unit ok; '; }
  catch (Exception e) { log += 'fee unit ERR ' + e.getMessage().left(150) + '; '; }
} else feeUom = fee[0].Id;
if (feeUom != null && mkt.DefaultUnitOfMeasureId != feeUom) {
  try { update new UsageResource(Id = mkt.Id, DefaultUnitOfMeasureId = feeUom); log += 'mkt unit switched; '; }
  catch (Exception e) {
    try { setStatus(mkt, 'Draft'); update new UsageResource(Id = mkt.Id, DefaultUnitOfMeasureId = feeUom); setStatus(mkt, 'Active'); log += 'mkt unit switched (via draft); '; }
    catch (Exception e2) { log += 'mkt unit ERR ' + e2.getMessage().left(150) + '; '; }
  }
}
// 3 policies for MKT and PAY, cloned from the SMS policy
ProductUsageResourcePolicy smsPol = [SELECT Id FROM ProductUsageResourcePolicy WHERE ProductUsageResource.Product.ProductCode = 'MB-SMS' LIMIT 1];
for (String c : new List<String>{ 'MB-MKT', 'MB-PAY' }) {
  ProductUsageResource pur = [SELECT Id FROM ProductUsageResource WHERE Product.ProductCode = :c LIMIT 1];
  if ([SELECT COUNT() FROM ProductUsageResourcePolicy WHERE ProductUsageResourceId = :pur.Id] == 0) {
    try { insert cl('ProductUsageResourcePolicy', smsPol.Id, new Map<String, Object>{ 'ProductUsageResourceId' => pur.Id, 'UsageAggregationPolicyId' => monthly, 'ProductSellingModelId' => evm }); log += c + ' policy ok; '; }
    catch (Exception e) { log += c + ' policy ERR ' + e.getMessage().left(150) + '; '; }
  }
}
// 4 grant binding policies
for (String c : prod.keySet()) if ([SELECT COUNT() FROM UsagePrdGrantBindingPolicy WHERE Product2Id = :prod.get(c).Id] == 0) {
  try { insert new UsagePrdGrantBindingPolicy(Name = c + ' Binding Policy', Product2Id = prod.get(c).Id, GrantBindingType = 'Self'); log += c + ' binding ok; '; }
  catch (Exception e) { log += c + ' binding ERR ' + e.getMessage().left(150) + '; '; }
}
// 5 rates on the SMS base rate card
List<SObject> toActivate = new List<SObject>();
Map<String, List<Object>> rates = new Map<String, List<Object>>{ 'MB-MKT' => new List<Object>{ 'MB_MKT_FIRST', 1.0 }, 'MB-PAY' => new List<Object>{ 'MB_PAY_TXN', 0.30 } };
for (String c : rates.keySet()) {
  UsageResource r = [SELECT Id, UnitOfMeasureClassId, DefaultUnitOfMeasureId FROM UsageResource WHERE Code = :(String) rates.get(c)[0]];
  if ([SELECT COUNT() FROM RateCardEntry WHERE RateCardId = :smsRce.RateCardId AND UsageResourceId = :r.Id AND Status IN ('Active','Draft')] == 0) {
    try {
      SObject e = cl('RateCardEntry', smsRce.Id, new Map<String, Object>{ 'ProductId' => prod.get(c).Id, 'UsageResourceId' => r.Id, 'ProductSellingModelId' => evm, 'Rate' => rates.get(c)[1], 'Status' => 'Draft' });
      insert e; toActivate.add(e); log += c + ' rate ok; ';
    } catch (Exception ex) { log += c + ' rate ERR ' + ex.getMessage().left(150) + '; '; }
  }
}
for (SObject e : toActivate) try { setStatus(e, 'Active'); log += 'rate active; '; } catch (Exception ex) { log += 'activate ERR ' + ex.getMessage().left(150) + '; '; }
// 6 rate card on the price books
for (Pricebook2 pb : [SELECT Id, Name FROM Pricebook2 WHERE IsActive = true AND (IsStandard = true OR Name LIKE 'North America%' OR Name LIKE 'United Kingdom%' OR Name LIKE 'Europe%' OR Name LIKE 'Australia%')])
  if ([SELECT COUNT() FROM PriceBookRateCard WHERE RateCardId = :smsRce.RateCardId AND PriceBookId = :pb.Id] == 0) {
    try { insert new PriceBookRateCard(RateCardId = smsRce.RateCardId, PriceBookId = pb.Id); log += 'linked ' + pb.Name + '; '; } catch (Exception e) { log += 'link ' + pb.Name + ' ERR ' + e.getMessage().left(120) + '; '; }
  }
System.debug(LoggingLevel.ERROR, 'QAU ' + log);
