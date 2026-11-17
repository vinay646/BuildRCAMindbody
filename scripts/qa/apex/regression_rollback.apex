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
