// CHANGES pricing data: copies the USD percentage tiers of the Mindbody schedules to GBP, EUR, AUD, CAD (deactivates the schedules, inserts, reactivates; all or nothing)
List<String> cur = new List<String>{'GBP','EUR','AUD','CAD'};
List<String> f = new List<String>();
for (Schema.SObjectField x : Schema.SObjectType.PriceAdjustmentTier.fields.getMap().values()) { Schema.DescribeFieldResult d = x.getDescribe(); if (d.isCreateable()) f.add(d.getName()); }
List<SObject> src = Database.query('SELECT ' + String.join(f, ',') + ' FROM PriceAdjustmentTier WHERE CurrencyIsoCode = \'USD\' AND PriceAdjustmentSchedule.Name LIKE \'Mindbody%\'');
Set<String> have = new Set<String>();
for (AggregateResult a : Database.query('SELECT PriceAdjustmentScheduleId s, CurrencyIsoCode c FROM PriceAdjustmentTier GROUP BY PriceAdjustmentScheduleId, CurrencyIsoCode')) have.add(a.get('s') + '|' + a.get('c'));
List<SObject> ins = new List<SObject>(); Integer amt = 0;
for (SObject t : src) {
  if (!String.valueOf(t.get('TierType')).containsIgnoreCase('percent')) { amt++; if (amt == 1) System.debug(LoggingLevel.ERROR, 'TYPE ' + t.get('TierType')); continue; }
  for (String c : cur) if (!have.contains(t.get('PriceAdjustmentScheduleId') + '|' + c)) { SObject n = t.clone(false, true); n.put('CurrencyIsoCode', c); ins.add(n); }
}
List<PriceAdjustmentSchedule> sch = [SELECT Id FROM PriceAdjustmentSchedule WHERE Name LIKE 'Mindbody%' AND IsActive = true];
Savepoint sp = Database.setSavepoint();
for (PriceAdjustmentSchedule s : sch) s.IsActive = false; update sch;
Database.SaveResult[] r = Database.insert(ins, false); Integer ok = 0; String err = '';
for (Database.SaveResult s : r) if (s.isSuccess()) ok++; else if (err.length() < 400) err += s.getErrors()[0].getMessage() + '; ';
System.debug(LoggingLevel.ERROR, 'TIERS src ' + src.size() + ' amountTiersSkipped ' + amt + ' inserted ' + ok + '/' + ins.size() + ' ' + err);
if (ok < ins.size()) { Database.rollback(sp); System.debug(LoggingLevel.ERROR, 'ROLLED BACK'); }
else { for (PriceAdjustmentSchedule s : sch) s.IsActive = true; update sch; System.debug(LoggingLevel.ERROR, 'REACTIVATED ' + sch.size()); }
