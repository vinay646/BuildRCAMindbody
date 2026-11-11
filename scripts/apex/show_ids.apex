// Read-only: record Ids the pricing procedure metadata needs (schedule constants).
for (SObject s : Database.query('SELECT Id, Name, ScheduleType, IsActive FROM PriceAdjustmentSchedule WHERE Name LIKE \'Mindbody%\' ORDER BY Name')) {
    System.debug(LoggingLevel.ERROR, 'SCHEDULE ' + s.get('Name') + ' = ' + s.Id + ' (' + s.get('ScheduleType') + ', active ' + s.get('IsActive') + ')');
}
for (SObject s : Database.query('SELECT Id, Name FROM Pricebook2 WHERE Name LIKE \'Mindbody%\'')) {
    System.debug(LoggingLevel.ERROR, 'PRICEBOOK ' + s.get('Name') + ' = ' + s.Id);
}
// Decision tables the pricing procedures' List Price / discount steps point at (LookUpId / LookUpApiName)
for (SObject d : Database.query('SELECT Id, DeveloperName, Status, SourceObject, UsageType FROM DecisionTable '
        + 'WHERE DeveloperName IN (\'Price_Book_Entry_Decision_Table_v2\', \'RLM_CostBookEntries\', '
        + '\'Contract_Pricing_Entries_Decision_Table\', \'Price_Adjustment_Tier_Decision_Table\', '
        + '\'Contract_Pricing_Volume_Tiers\', \'Attribute_Based_Adjustment_Decision_Table\', '
        + '\'Bundle_Based_Adjustment_Decision_Table\', \'Index_Rate_Decision_Table\') ORDER BY DeveloperName')) {
    System.debug(LoggingLevel.ERROR, 'DECISIONTABLE ' + d.get('DeveloperName') + ' = ' + d.Id + ' (' + d.get('Status')
        + ', ' + d.get('SourceObject') + ', ' + d.get('UsageType') + ')');
}
