// Read-only: user permissions about configuration rules, and who has them.
Map<String, Schema.SObjectField> f = Schema.SObjectType.PermissionSet.fields.getMap();
List<String> hits = new List<String>();
for (String k : f.keySet()) {
    String n = f.get(k).getDescribe().getName();
    String l = n.toLowerCase();
    if (l.startsWith('permissions') && (l.contains('rule') || l.contains('configurator') || l.contains('constraint'))) hits.add(n);
}
hits.sort();
System.debug(LoggingLevel.ERROR, 'USERPERMS ' + String.join(hits, ', '));
for (String p : hits) {
    List<String> sets = new List<String>();
    for (SObject ps : Database.query('SELECT Name, Label, IsOwnedByProfile FROM PermissionSet WHERE ' + p + ' = true LIMIT 40')) {
        sets.add((Boolean) ps.get('IsOwnedByProfile') ? 'profile:' + ps.get('Label') : String.valueOf(ps.get('Name')));
    }
    Integer mine = Database.countQuery('SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = \'' + UserInfo.getUserId() + '\' AND PermissionSet.' + p + ' = true');
    System.debug(LoggingLevel.ERROR, 'PERM ' + p + ' | running user has it: ' + (mine > 0) + ' | granted by: ' + String.join(sets, ', '));
}
// Object access on ProductConfigurationRule for the running user
Schema.DescribeSObjectResult d = Schema.getGlobalDescribe().get('productconfigurationrule').getDescribe();
System.debug(LoggingLevel.ERROR, 'OBJECT ProductConfigurationRule createable=' + d.isCreateable() + ' updateable=' + d.isUpdateable() + ' deletable=' + d.isDeletable());
for (Schema.SObjectField sf : d.fields.getMap().values()) {
    Schema.DescribeFieldResult x = sf.getDescribe();
    if (!x.isCustom()) System.debug(LoggingLevel.ERROR, '  FIELD ' + x.getName() + ' create=' + x.isCreateable() + ' update=' + x.isUpdateable() + ' ' + x.getType());
}
