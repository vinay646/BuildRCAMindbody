// Read-only: record Ids the pricing procedure metadata needs (schedule constants).
for (SObject s : Database.query('SELECT Id, Name, ScheduleType, IsActive FROM PriceAdjustmentSchedule WHERE Name LIKE \'Mindbody%\' ORDER BY Name')) {
    System.debug(LoggingLevel.ERROR, 'SCHEDULE ' + s.get('Name') + ' = ' + s.Id + ' (' + s.get('ScheduleType') + ', active ' + s.get('IsActive') + ')');
}
for (SObject s : Database.query('SELECT Id, Name FROM Pricebook2 WHERE Name LIKE \'Mindbody%\'')) {
    System.debug(LoggingLevel.ERROR, 'PRICEBOOK ' + s.get('Name') + ' = ' + s.Id);
}
