// Read-only: pricing recipes and which decision table each pricing component (ListPrice, VolumeDiscount, ...) may use.
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
for (String o : new List<String>{ 'PricingRecipe', 'PricingRecipeTableMapping', 'PricingProcedureRecipe' }) {
    if (!gd.containsKey(o.toLowerCase())) {
        System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ': not available');
        continue;
    }
    Map<String, Schema.SObjectField> f = gd.get(o.toLowerCase()).getDescribe().fields.getMap();
    List<String> cols = new List<String>();
    for (String k : f.keySet()) {
        Schema.DescribeFieldResult d = f.get(k).getDescribe();
        if (!d.isCustom() && !k.endsWith('date') && !k.endsWith('byid') && k != 'systemmodstamp' && k != 'isdeleted'
                && d.getType() != Schema.DisplayType.TEXTAREA) {
            cols.add(d.getName());
        }
    }
    System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ' fields: ' + String.join(cols, ', '));
    for (SObject r : Database.query('SELECT ' + String.join(cols, ', ') + ' FROM ' + o + ' LIMIT 200')) {
        List<String> parts = new List<String>();
        for (String c : cols) {
            if (r.get(c) != null) {
                parts.add(c + '=' + r.get(c));
            }
        }
        System.debug(LoggingLevel.ERROR, '  ' + o + ': ' + String.join(parts, ', '));
    }
}
