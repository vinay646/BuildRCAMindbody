// Read-only: price adjustment tiers by schedule and currency; T06 account contacts
String o='';
for (AggregateResult a : Database.query('SELECT PriceAdjustmentSchedule.Name n, CurrencyIsoCode c, COUNT(Id) k FROM PriceAdjustmentTier GROUP BY PriceAdjustmentSchedule.Name, CurrencyIsoCode')) o+=a.get('n')+'/'+a.get('c')+'='+a.get('k')+'; ';
for (PriceAdjustmentSchedule s : Database.query('SELECT Name, CurrencyIsoCode, IsActive FROM PriceAdjustmentSchedule')) o+=' S:'+s.Name+'/'+s.get('CurrencyIsoCode')+'/'+s.IsActive;
o+=' | contacts: '+[SELECT COUNT() FROM Contact WHERE Account.Name LIKE 'MB T06 UK%'];
System.debug(LoggingLevel.ERROR, 'P2 '+o);
