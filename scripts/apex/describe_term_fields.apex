// Read-only: term-related fields on Quote and QuoteLineItem
for (String o : new List<String>{ 'Quote', 'QuoteLineItem' }) {
    for (Schema.SObjectField f : Schema.getGlobalDescribe().get(o).getDescribe().fields.getMap().values()) {
        Schema.DescribeFieldResult d = f.getDescribe();
        String n = d.getName().toLowerCase();
        if (n.contains('term') || n.contains('startdate') || n.contains('enddate')) {
            System.debug(LoggingLevel.ERROR, 'FIELD ' + o + '.' + d.getName() + ' ' + d.getType() + ' "' + d.getLabel() + '"');
        }
    }
}
