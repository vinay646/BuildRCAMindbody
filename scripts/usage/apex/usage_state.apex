// Read-only: usage setup state for MB-SMS, MB-MKT, MB-ULT, MB-PAY (resources, policies, grants, rate cards, PBEs)
String o='';
String[] qs = new String[]{
 'SELECT ProductCode, UsageModelType FROM Product2 WHERE ProductCode IN (\'MB-SMS\',\'MB-MKT\',\'MB-ULT\',\'MB-PAY\')',
 'SELECT Product.ProductCode, UsageResource.Code FROM ProductUsageResource WHERE Product.ProductCode LIKE \'MB-%\'',
 'SELECT ProductUsageResource.Product.ProductCode, ProductSellingModel.Name FROM ProductUsageResourcePolicy WHERE ProductUsageResource.Product.ProductCode LIKE \'MB-%\'',
 'SELECT ProductUsageResource.Product.ProductCode, Quantity FROM ProductUsageGrant WHERE ProductUsageResource.Product.ProductCode LIKE \'MB-%\'',
 'SELECT Product2.ProductCode, CurrencyIsoCode, UnitPrice, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode IN (\'MB-SMS\',\'MB-MKT\',\'MB-PAY\') AND IsActive = true AND Pricebook2.IsStandard = false AND CurrencyIsoCode = \'USD\'',
 'SELECT Name, Code FROM UsageResource',
 'SELECT Name FROM RateCard',
 'SELECT RateCard.Name, UsageResource.Code, Rate, CurrencyIsoCode FROM RateCardEntry LIMIT 30',
 'SELECT Name FROM UsageResourceBillingPolicy',
 'SELECT Name FROM ProductSellingModel'};
for (String s : qs) {
  o += ' ## ' + s.substringBetween('FROM ', ' ') + ': ';
  try { for (SObject r : Database.query(s)) { Map<String,Object> m = r.getPopulatedFieldsAsMap(); String row=''; for (String k : m.keySet()) if (k!='Id') { Object v=m.get(k); if (v instanceof SObject) { Map<String,Object> m2=((SObject)v).getPopulatedFieldsAsMap(); for (String k2:m2.keySet()) if(k2!='Id'){Object v2=m2.get(k2); row+=(v2 instanceof SObject? String.valueOf(((SObject)v2).get('ProductCode')):String.valueOf(v2))+'/';} } else row+=v+'/'; } o+=row+'; '; } }
  catch (Exception e) { o += 'ERR ' + e.getMessage().left(120); }
}
System.debug(LoggingLevel.ERROR, 'US '+o);
