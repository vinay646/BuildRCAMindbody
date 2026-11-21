// CHANGES setup data: usage for MB-SMS (SMS overage, USD 0.008/text) and MB-MKT (marketplace fee, money, USD 1 per USD), cloned from the working CS-25Gb setup. Idempotent.
String log = '';
SObject cl(String obj, Id srcId, Map<String, Object> ov) {
  List<String> f = new List<String>();
  for (Schema.SObjectField x : Schema.getGlobalDescribe().get(obj).getDescribe().fields.getMap().values()) { Schema.DescribeFieldResult d = x.getDescribe(); if (d.isCreateable()) f.add(d.getName()); }
  SObject s = Database.query('SELECT ' + String.join(f, ',') + ' FROM ' + obj + ' WHERE Id = :srcId')[0].clone(false, true);
  for (String k : ov.keySet()) try { s.put(k, ov.get(k)); } catch (Exception e) { log += 'skip ' + obj + '.' + k + '; '; }
  if (s.getSObjectType().getDescribe().fields.getMap().containsKey('status') && new Set<String>{'UnitOfMeasureClass','UnitOfMeasure','UsageResource','ProductUsageResource','RateCardEntry','ProductUsageGrant'}.contains(obj)) s.put('Status', 'Draft');
  return s;
}
List<SObject> toActivate = new List<SObject>();
SObject ins(SObject s, String tag) { try { insert s; if (s.get('Id') != null && s.getSObjectType().getDescribe().fields.getMap().containsKey('status') && s.get('Status') == 'Draft') toActivate.add(s); log += tag + ' ok; '; return s; } catch (Exception e) { log += tag + ' ERR ' + e.getMessage().left(160) + '; '; return null; } }
Product2 cs = [SELECT Id FROM Product2 WHERE ProductCode = 'CS-25Gb'];
ProductUsageResource csPur = [SELECT Id, UsageResourceId FROM ProductUsageResource WHERE ProductId = :cs.Id LIMIT 1];
UsageResource csUr = [SELECT Id, UnitOfMeasureClassId, DefaultUnitOfMeasureId FROM UsageResource WHERE Id = :csPur.UsageResourceId];
ProductUsageResourcePolicy csPol = [SELECT Id, RatingFrequencyPolicyId, UsageOveragePolicyId FROM ProductUsageResourcePolicy WHERE ProductUsageResourceId = :csPur.Id LIMIT 1];
Id aggId = [SELECT Id FROM UsageResourceBillingPolicy WHERE Name = 'Monthly Total' LIMIT 1].Id;
RateCardEntry csRce = [SELECT Id, RateUnitOfMeasureClassId, RateUnitOfMeasureId FROM RateCardEntry WHERE ProductId = :cs.Id AND RateCardType = 'Base' LIMIT 1];
Id evm = [SELECT Id FROM ProductSellingModel WHERE Name = 'Evergreen Monthly' LIMIT 1].Id;
// 1 UoM classes + UoMs (count type, cloned from the CS class): texts, and fee amount (1 unit = 1 currency unit, so the fee is rated at 1.00)
Map<String, Id[]> uoms = new Map<String, Id[]>();
for (String[] d : new List<String[]>{ new String[]{ 'Texts', 'TEXTS', 'Text', 'TXT' }, new String[]{ 'Fee Amount', 'FEEAMT', 'Fee Unit', 'FEEU' } }) {
  Id cId, uId;
  List<UnitOfMeasureClass> uc = [SELECT Id FROM UnitOfMeasureClass WHERE Name = :d[0]];
  if (uc.isEmpty()) cId = ins(cl('UnitOfMeasureClass', csUr.UnitOfMeasureClassId, new Map<String, Object>{ 'Name' => d[0], 'Code' => d[1] }), 'uomClass ' + d[1])?.Id; else cId = uc[0].Id;
  List<UnitOfMeasure> uu = [SELECT Id FROM UnitOfMeasure WHERE UnitOfMeasureClassId = :cId];
  if (uu.isEmpty() && cId != null) uId = ins(cl('UnitOfMeasure', csUr.DefaultUnitOfMeasureId, new Map<String, Object>{ 'Name' => d[2], 'UnitCode' => d[3], 'UnitOfMeasureClassId' => cId }), 'uom ' + d[3])?.Id; else if (!uu.isEmpty()) uId = uu[0].Id;
  if (cId != null && uId != null) { UnitOfMeasureClass c = new UnitOfMeasureClass(Id = cId); c.put('DefaultUnitOfMeasureId', uId); try { update c; } catch (Exception e) { log += 'classDefault ' + e.getMessage().left(80) + '; '; } }
  uoms.put(d[1], new Id[]{ cId, uId });
}
Id txtClass = uoms.get('TEXTS')[0], txtUom = uoms.get('TEXTS')[1];
// rate card
List<RateCard> rcs = [SELECT Id FROM RateCard WHERE Name = 'Mindbody Usage Base'];
Id rcId = rcs.isEmpty() ? ins(cl('RateCard', [SELECT RateCardId FROM RateCardEntry WHERE Id = :csRce.Id].RateCardId, new Map<String, Object>{ 'Name' => 'Mindbody Usage Base' }), 'rateCard')?.Id : rcs[0].Id;
// per product
Map<String, List<Object>> spec = new Map<String, List<Object>>{
  'MB-SMS' => new List<Object>{ 'SMS Messages', 'MB-UR-SMS', txtClass, txtUom, 0.008 },
  'MB-MKT' => new List<Object>{ 'Marketplace New-Client Fees', 'MB-UR-MKT', uoms.get('FEEAMT')[0], uoms.get('FEEAMT')[1], 1.0 } };
for (String code : spec.keySet()) {
  List<Object> s = spec.get(code);
  Product2 p = [SELECT Id, UsageModelType FROM Product2 WHERE ProductCode = :code];
  if (p.UsageModelType != 'Anchor') { p.UsageModelType = 'Anchor'; try { update p; log += code + ' anchor; '; } catch (Exception e) { log += code + ' anchor ERR ' + e.getMessage().left(120) + '; '; } }
  List<UsageResource> urs = [SELECT Id FROM UsageResource WHERE Code = :(String) s[1]];
  Id urId = urs.isEmpty() ? ins(cl('UsageResource', csUr.Id, new Map<String, Object>{ 'Name' => s[0], 'Code' => s[1], 'UsageDefinitionProductId' => p.Id, 'UnitOfMeasureClassId' => s[2], 'DefaultUnitOfMeasureId' => s[3] }), code + ' resource')?.Id : urs[0].Id;
  if (urId == null) continue;
  List<ProductUsageResource> purs = [SELECT Id FROM ProductUsageResource WHERE ProductId = :p.Id AND UsageResourceId = :urId];
  Id purId = purs.isEmpty() ? ins(cl('ProductUsageResource', csPur.Id, new Map<String, Object>{ 'ProductId' => p.Id, 'UsageResourceId' => urId, 'EffectiveStartDate' => Datetime.newInstanceGmt(2026, 1, 1) }), code + ' PUR')?.Id : purs[0].Id;
  if (purId == null) continue;
  if ([SELECT COUNT() FROM ProductUsageResourcePolicy WHERE ProductUsageResourceId = :purId] == 0)
    ins(cl('ProductUsageResourcePolicy', csPol.Id, new Map<String, Object>{ 'ProductUsageResourceId' => purId, 'ProductSellingModelId' => evm, 'UsageAggregationPolicyId' => aggId }), code + ' PURP');
  if ([SELECT COUNT() FROM UsagePrdGrantBindingPolicy WHERE Product2Id = :p.Id] == 0)
    ins(new UsagePrdGrantBindingPolicy(Name = code + ' Binding Policy', Product2Id = p.Id, GrantBindingType = 'Self'), code + ' binding');
  if (rcId != null && [SELECT COUNT() FROM RateCardEntry WHERE RateCardId = :rcId AND UsageResourceId = :urId AND Status IN ('Active','Draft')] == 0)
    ins(cl('RateCardEntry', csRce.Id, new Map<String, Object>{ 'RateCardId' => rcId, 'ProductId' => p.Id, 'UsageResourceId' => urId, 'ProductSellingModelId' => evm, 'Rate' => s[4], 'EffectiveFrom' => Datetime.newInstanceGmt(2026, 1, 1), 'DefaultUnitOfMeasureClassId' => s[2], 'DefaultUnitOfMeasureId' => s[3] }), code + ' rate');
}
// link rate card to the Mindbody USD price book
if (rcId != null) for (Pricebook2 pb : [SELECT Id FROM Pricebook2 WHERE Name IN ('North America & Asia (USD)', 'Standard Price Book')])
  if ([SELECT COUNT() FROM PriceBookRateCard WHERE RateCardId = :rcId AND PriceBookId = :pb.Id] == 0) ins(new PriceBookRateCard(RateCardId = rcId, PriceBookId = pb.Id), 'pbRateCard');
// activate: UoM, class, resources, product usage resources, rate entries (in creation order, then retry once)
for (Integer pass = 0; pass < 2; pass++) for (SObject r : toActivate) if (r.get('Status') != 'Active') {
  SObject u = r.getSObjectType().newSObject((Id) r.get('Id')); u.put('Status', 'Active');
  try { update u; r.put('Status', 'Active'); log += 'activated ' + r.getSObjectType() + '; '; } catch (Exception e) { if (pass == 1) log += 'activate ' + r.getSObjectType() + ' ERR ' + e.getMessage().left(140) + '; '; }
}
System.debug(LoggingLevel.ERROR, 'UB ' + log);
