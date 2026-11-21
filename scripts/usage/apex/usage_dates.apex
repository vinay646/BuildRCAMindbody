// CHANGES setup data: backdates the Mindbody usage records (product usage resources, rate card, rate entries) to 2026-01-01 so orders starting before Nov are covered
Datetime d = Datetime.newInstanceGmt(2026, 1, 1);
String log = '';
List<SObject> recs = new List<SObject>();
recs.addAll((List<SObject>) [SELECT Id, EffectiveStartDate, Status FROM ProductUsageResource WHERE Product.ProductCode IN ('MB-SMS','MB-MKT')]);
recs.addAll((List<SObject>) [SELECT Id, EffectiveFrom FROM RateCard WHERE Name = 'Mindbody Usage Base']);
recs.addAll((List<SObject>) [SELECT Id, EffectiveFrom, Status FROM RateCardEntry WHERE RateCard.Name = 'Mindbody Usage Base']);
for (SObject r : recs) {
  String f = r.getSObjectType() == ProductUsageResource.SObjectType ? 'EffectiveStartDate' : 'EffectiveFrom';
  SObject u = r.getSObjectType().newSObject(r.Id); u.put(f, d);
  try { update u; log += r.getSObjectType() + ' ok; '; }
  catch (Exception e) {
    try { SObject x = r.getSObjectType().newSObject(r.Id); x.put('Status', 'Draft'); update x; update u; x.put('Status', 'Active'); update x; log += r.getSObjectType() + ' ok(via draft); '; }
    catch (Exception e2) { log += r.getSObjectType() + ' ERR ' + e2.getMessage().left(150) + '; '; }
  }
}
System.debug(LoggingLevel.ERROR, 'UD ' + log);
