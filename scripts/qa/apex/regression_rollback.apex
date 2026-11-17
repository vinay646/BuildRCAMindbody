// QA regression probe: every insert is rolled back (Database.rollback) - nothing is saved.
String stage;
for (Schema.PicklistEntry p : Opportunity.StageName.getDescribe().getPicklistValues()) { if (p.isActive()) { stage = p.getValue(); break; } }
Map<String, String> pbByRegion = new Map<String, String>{ 'NA' => 'North America & Asia (USD)', 'UK' => 'United Kingdom', 'AU' => 'Australia', 'EU' => 'Europe' };
Map<String, String> curByRegion = new Map<String, String>{ 'NA' => 'USD', 'UK' => 'GBP', 'AU' => 'AUD', 'EU' => 'EUR' };
for (String r : pbByRegion.keySet()) {
    List<Account> a = Database.query('SELECT Id, Name FROM Account WHERE Region__c = :r ORDER BY CreatedDate DESC LIMIT 1');
    if (a.isEmpty()) { System.debug(LoggingLevel.ERROR, 'RESULT opp ' + r + ': no account'); continue; }
    for (Integer withPb = 0; withPb < 2; withPb++) {
        Savepoint sp = Database.setSavepoint();
        try {
            Opportunity o = new Opportunity(Name = 'QA rollback test', StageName = stage, CloseDate = Date.today().addDays(30), AccountId = a[0].Id);
            if (withPb == 1) {
                o.Pricebook2Id = [SELECT Id FROM Pricebook2 WHERE Name = :pbByRegion.get(r) LIMIT 1].Id;
                o.put('CurrencyIsoCode', curByRegion.get(r));
            }
            insert o;
            SObject s = Database.query('SELECT Pricebook2.Name, CurrencyIsoCode FROM Opportunity WHERE Id = \'' + o.Id + '\'');
            System.debug(LoggingLevel.ERROR, 'RESULT opp ' + r + (withPb == 1 ? ' (price book given)' : ' (no price book, as from the New button)') + ': SAVED, price book after flow = ' + ((Opportunity) s).Pricebook2?.Name + ' ' + s.get('CurrencyIsoCode') + ' | account ' + a[0].Name);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'RESULT opp ' + r + (withPb == 1 ? ' (price book given)' : ' (no price book, as from the New button)') + ': BLOCKED ' + e.getMessage().left(300) + ' | account ' + a[0].Name);
        }
        Database.rollback(sp);
    }
}
// Starter line with blank / Monthly / Quarterly billing frequency on an empty USD quote
List<Quote> qs = [SELECT Id, QuoteNumber, Pricebook2Id, Pricebook2.Name FROM Quote WHERE Pricebook2.Name = 'North America & Asia (USD)' AND Id NOT IN (SELECT QuoteId FROM QuoteLineItem) ORDER BY CreatedDate DESC LIMIT 1];
if (qs.isEmpty()) { System.debug(LoggingLevel.ERROR, 'RESULT starter: no empty USD quote'); }
else {
    Quote q = qs[0];
    List<PricebookEntry> pbes = [SELECT Id, UnitPrice, Product2Id, ProductSellingModelId, ProductSellingModel.Name FROM PricebookEntry WHERE Pricebook2Id = :q.Pricebook2Id AND Product2.ProductCode = 'MB-STR' AND CurrencyIsoCode = 'USD' AND IsActive = true];
    for (PricebookEntry pbe : pbes) {
        for (String f : new List<String>{ null, 'Monthly', 'Quarterly' }) {
            Savepoint sp = Database.setSavepoint();
            String label = 'RESULT starter ' + pbe.ProductSellingModel.Name + ' freq=' + (f == null ? 'blank' : f) + ' on quote ' + q.QuoteNumber + ': ';
            try {
                QuoteLineItem l = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = pbe.Product2Id, Quantity = 1, UnitPrice = pbe.UnitPrice, ProductSellingModelId = pbe.ProductSellingModelId, StartDate = Date.today());
                if (f != null) { l.put('BillingFrequency', f); }
                insert l;
                SObject s = Database.query('SELECT BillingFrequency FROM QuoteLineItem WHERE Id = \'' + l.Id + '\'');
                System.debug(LoggingLevel.ERROR, label + 'SAVED, billing frequency stored = ' + s.get('BillingFrequency'));
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, label + 'BLOCKED ' + e.getMessage().left(300));
            }
            Database.rollback(sp);
        }
    }
}
