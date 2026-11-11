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
// Product Configuration Rules with their stored definition (the format the loader reproduces)
if (gd.containsKey('productconfigurationrule')) {
    for (SObject r : Database.query('SELECT Id, Name, ApiName, RuleType, RuleSubType, ProcessScope, Status, Sequence, Description, '
            + 'ConfigurationRuleDefinition FROM ProductConfigurationRule ORDER BY CreatedDate LIMIT 20')) {
        System.debug(LoggingLevel.ERROR, 'CONFIGRULE ' + r.get('Name') + ' | ApiName=' + r.get('ApiName') + ' | ' + r.get('RuleType')
            + '/' + r.get('RuleSubType') + '/' + r.get('ProcessScope') + ' | ' + r.get('Status') + ' | seq ' + r.get('Sequence'));
        System.debug(LoggingLevel.ERROR, 'CONFIGRULE-DEFINITION ' + String.valueOf(r.get('ConfigurationRuleDefinition')).replaceAll('[\\r\\n]+', ' '));
    }
}
// Rule libraries behind Configuration Rules (Business Rules Engine) and the running user's rule-related permissions
for (String o : new List<String>{ 'RuleLibrary', 'RuleLibraryVersion', 'RuleLibraryDefinition', 'BusinessRuleLibrary' }) {
    if (!gd.containsKey(o.toLowerCase())) {
        System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ': not available');
        continue;
    }
    Map<String, Schema.SObjectField> f = gd.get(o.toLowerCase()).getDescribe().fields.getMap();
    List<String> cols = new List<String>();
    for (String k : f.keySet()) {
        Schema.DescribeFieldResult d = f.get(k).getDescribe();
        if (!d.isCustom() && !k.endsWith('byid') && k != 'systemmodstamp' && k != 'isdeleted'
                && d.getType() != Schema.DisplayType.TEXTAREA && d.getType() != Schema.DisplayType.BASE64) {
            cols.add(d.getName());
        }
    }
    System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ' fields: ' + String.join(cols, ', '));
    for (SObject r : Database.query('SELECT ' + String.join(cols, ', ') + ' FROM ' + o + ' LIMIT 50')) {
        System.debug(LoggingLevel.ERROR, '  ' + o + ': ' + r);
    }
}
for (PermissionSetAssignment a : [SELECT PermissionSet.Name, PermissionSet.Label FROM PermissionSetAssignment
        WHERE AssigneeId = :UserInfo.getUserId() ORDER BY PermissionSet.Label]) {
    System.debug(LoggingLevel.ERROR, 'MY PERMSET ' + a.PermissionSet.Label + ' (' + a.PermissionSet.Name + ')');
}
for (PermissionSet p : [SELECT Name, Label FROM PermissionSet WHERE IsOwnedByProfile = false
        AND (Label LIKE '%Rule%' OR Label LIKE '%Configurat%' OR Label LIKE '%Business Rules%' OR Name LIKE '%Rule%')
        ORDER BY Label LIMIT 50]) {
    System.debug(LoggingLevel.ERROR, 'RULE PERMSET AVAILABLE ' + p.Label + ' (' + p.Name + ')');
}
for (PermissionSetLicense l : [SELECT MasterLabel, DeveloperName, Status, TotalLicenses, UsedLicenses FROM PermissionSetLicense
        WHERE MasterLabel LIKE '%Rule%' OR MasterLabel LIKE '%Revenue%' OR MasterLabel LIKE '%Configur%' LIMIT 30]) {
    System.debug(LoggingLevel.ERROR, 'PSL ' + l.MasterLabel + ' (' + l.DeveloperName + ') ' + l.Status + ' ' + l.UsedLicenses + '/' + l.TotalLicenses);
}
