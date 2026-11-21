// Read-only: usage setup state for MB-SMS, MB-MKT, MB-ULT (resources, policies, grants, rate cards, PBEs)
String o='';
for (Product2 p : [SELECT Id, ProductCode, UsageModelType, IsActive FROM Product2 WHERE ProductCode IN ('MB-SMS','MB-MKT','MB-ULT','MB-PAY')]) {
  o+='\n'+p.ProductCode+' model='+p.UsageModelType+' active='+p.IsActive;
  for (ProductUsageResource r : [SELECT Id, UsageResource.Name, UsageResource.Code, IsActive FROM ProductUsageResource WHERE ProductId=:p.Id]) {
    o+=' | PUR '+r.UsageResource.Name+'/'+r.UsageResource.Code+'/'+r.IsActive+' policies='+[SELECT COUNT() FROM ProductUsageResourcePolicy WHERE ProductUsageResourceId=:r.Id];
  }
  o+=' | grants='+[SELECT COUNT() FROM ProductUsageGrant WHERE ProductUsageResource.ProductId=:p.Id];
  for (PricebookEntry e : [SELECT CurrencyIsoCode, UnitPrice, ProductSellingModel.Name FROM PricebookEntry WHERE Product2Id=:p.Id AND IsActive=true AND Pricebook2.IsStandard=false LIMIT 4]) o+=' | PBE '+e.CurrencyIsoCode+' '+e.UnitPrice+' '+e.ProductSellingModel.Name;
}
o+='\nUR: '; for (UsageResource u : [SELECT Name, Code, Status FROM UsageResource]) o+=u.Name+'/'+u.Code+'/'+u.Status+'; ';
o+='\nRC: '; for (RateCard c : [SELECT Name, Type FROM RateCard]) o+=c.Name+'/'+c.Type+'; ';
o+='\nRCE count by resource: '; for (AggregateResult a : [SELECT UsageResource.Code c, COUNT(Id) k FROM RateCardEntry GROUP BY UsageResource.Code]) o+=a.get('c')+'='+a.get('k')+'; ';
o+='\nURBP: '; for (UsageResourceBillingPolicy b : [SELECT Name FROM UsageResourceBillingPolicy]) o+=b.Name+'; ';
System.debug(LoggingLevel.ERROR, 'US '+o.replace('\n',' ## '));
