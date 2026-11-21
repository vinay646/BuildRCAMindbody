// Read-only: checks GBP, UK legal entity, MB-ACC GBP prices, UK VAT treatment
String o='';
try { for (SObject c : Database.query('SELECT IsoCode, IsActive FROM CurrencyType')) o+=c.get('IsoCode')+':'+c.get('IsActive')+' '; } catch(Exception e){ o+='noMultiCurrency '; }
o+='| LE: '; for (LegalEntity l : [SELECT Name, LegalEntityCountry FROM LegalEntity]) o+=l.Name+'/'+l.LegalEntityCountry+'; ';
o+='| PBE: '; for (PricebookEntry p : Database.query('SELECT Pricebook2.Name, UnitPrice, CurrencyIsoCode, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode=\'MB-ACC\' AND IsActive=true')) o+=p.Pricebook2.Name+' '+p.get('CurrencyIsoCode')+' '+p.UnitPrice+' '+p.ProductSellingModel.Name+'; ';
o+='| BT: '; for (BillingTreatment b : [SELECT Name, LegalEntity.Name, Status FROM BillingTreatment]) o+=b.Name+'/'+b.LegalEntity.Name+'/'+b.Status+'; ';
o+='| TT: '; for (TaxTreatment t : [SELECT Name, LegalEntity.Name, Status FROM TaxTreatment]) o+=t.Name+'/'+t.LegalEntity.Name+'/'+t.Status+'; ';
System.debug(LoggingLevel.ERROR, 'T06 '+o);
