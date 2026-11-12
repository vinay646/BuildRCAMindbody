// Read-only: Quote Line fields usable to count tier / repeated lines on a quote (CR-01, CFG-13)
for (Schema.SObjectField f : QuoteLineItem.SObjectType.getDescribe().fields.getMap().values()) {
    Schema.DescribeFieldResult d = f.getDescribe();
    if (d.isCustom() || d.getType() == Schema.DisplayType.STRING || d.getType() == Schema.DisplayType.PICKLIST || d.getType() == Schema.DisplayType.REFERENCE || d.getType() == Schema.DisplayType.BOOLEAN) {
        System.debug(LoggingLevel.ERROR, 'FIELD QuoteLineItem.' + d.getName() + ' ' + d.getType() + (d.isCalculated() ? ' formula' : '') + (d.isCustom() ? ' custom' : '') + ' "' + d.getLabel() + '"');
    }
}
for (QuoteLineItem q : [SELECT Quote.Name, Product2.ProductCode, Product2.Family, ParentQuoteLineItemId FROM QuoteLineItem WHERE Quote.Account.Name = 'Pulse Fitness Brands' ORDER BY CreatedDate DESC LIMIT 30]) {
    System.debug(LoggingLevel.ERROR, 'LINE ' + q.Quote.Name + ' | ' + q.Product2.ProductCode + ' | ' + q.Product2.Family + ' | parent=' + q.ParentQuoteLineItemId);
}
