// Read-only: describes the standard ARM pricing objects (picklist values, fields) and checks which optional
// pricing features exist (promotions, term-based adjustments). Used by the 'explore' workflow action.
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
List<String> out = new List<String>();
List<String> objs = new List<String>{
    'PriceAdjustmentSchedule', 'PriceAdjustmentTier', 'AttributeBasedAdjustment', 'AttributeBasedAdjRule',
    'BundleBasedAdjustment', 'ContractItemPrice', 'ContractItemPriceAdjTier', 'PricebookEntryDerivedPrice',
    'CostBook', 'CostBookEntry', 'Promotion', 'PromotionSegment', 'PromotionQualifier', 'PromotionTarget',
    'Coupon', 'PromotionLineItemRule', 'PriceAdjustmentMatrix', 'QuoteLineItem', 'QuoteLinePriceAdjustment',
    'QuoteLineGroup', 'OrderItem', 'ProductSellingModel'
};
for (String o : objs) {
    if (!gd.containsKey(o.toLowerCase())) {
        out.add('OBJECT ' + o + ': not available');
        continue;
    }
    Map<String, Schema.SObjectField> f = gd.get(o.toLowerCase()).getDescribe().fields.getMap();
    List<String> names = new List<String>();
    for (String k : f.keySet()) {
        Schema.DescribeFieldResult d = f.get(k).getDescribe();
        if (d.isCustom()) {
            continue;
        }
        String n = d.getName();
        if (d.getType() == Schema.DisplayType.PICKLIST || d.getType() == Schema.DisplayType.MULTIPICKLIST) {
            List<String> v = new List<String>();
            for (Schema.PicklistEntry e : d.getPicklistValues()) {
                v.add(e.getValue());
            }
            n += '[' + String.join(v, '|') + ']';
        } else if (d.getType() == Schema.DisplayType.REFERENCE) {
            n += '->' + String.valueOf(d.getReferenceTo());
        }
        names.add(n);
    }
    names.sort();
    // QuoteLineItem / OrderItem are big: only the pricing-related fields
    if (o == 'QuoteLineItem' || o == 'OrderItem') {
        List<String> keep = new List<String>();
        for (String n : names) {
            String l = n.toLowerCase();
            if (l.contains('price') || l.contains('discount') || l.contains('term') || l.contains('frequen')
                    || l.contains('adjust') || l.contains('sellingmodel') || l.contains('period') || l.contains('billing')) {
                keep.add(n);
            }
        }
        names = keep;
    }
    out.add('OBJECT ' + o + ': ' + String.join(names, ', '));
}
for (String o : new List<String>{ 'PriceAdjustmentSchedule', 'PriceAdjustmentTier', 'Promotion' }) {
    if (gd.containsKey(o.toLowerCase())) {
        out.add('COUNT ' + o + ': ' + Database.countQuery('SELECT COUNT() FROM ' + o));
    }
}
for (String l : out) {
    System.debug(LoggingLevel.ERROR, l);
}
