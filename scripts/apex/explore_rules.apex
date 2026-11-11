// Read-only: objects behind constraint models (CML) and product qualification in this release.
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
List<String> objs = new List<String>{ 'ExpressionSetConstraintObj', 'ProductQualification', 'ProductDisqualification',
    'ProductCategoryQualification', 'ProductCategoryDisqual', 'QualificationProcedure', 'ProductConfigurationRule',
    'ProductConfigurationFlow', 'ProductConfigFlowAssignment', 'ConfiguratorRule' };
for (String o : objs) {
    if (!gd.containsKey(o.toLowerCase())) {
        System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ': not available');
        continue;
    }
    Map<String, Schema.SObjectField> f = gd.get(o.toLowerCase()).getDescribe().fields.getMap();
    List<String> names = new List<String>();
    for (String k : f.keySet()) {
        Schema.DescribeFieldResult d = f.get(k).getDescribe();
        if (d.isCustom() || k.endsWith('date') || k.endsWith('byid') || k == 'systemmodstamp' || k == 'isdeleted') {
            continue;
        }
        String n = d.getName();
        if (d.getType() == Schema.DisplayType.PICKLIST) {
            List<String> v = new List<String>();
            for (Schema.PicklistEntry e : d.getPicklistValues()) { v.add(e.getValue()); }
            n += '[' + String.join(v, '|') + ']';
        } else if (d.getType() == Schema.DisplayType.REFERENCE) {
            n += '->' + String.valueOf(d.getReferenceTo());
        }
        names.add(n);
    }
    names.sort();
    System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ': ' + String.join(names, ', '));
    System.debug(LoggingLevel.ERROR, 'COUNT ' + o + ': ' + Database.countQuery('SELECT COUNT() FROM ' + o));
}
if (gd.containsKey('expressionsetconstraintobj')) {
    for (SObject r : Database.query('SELECT Id, ExpressionSetId, ReferenceObjectId, ConstraintModelTag, ConstraintModelTagType FROM ExpressionSetConstraintObj LIMIT 30')) {
        System.debug(LoggingLevel.ERROR, '  CONSTRAINTOBJ ' + r);
    }
}
