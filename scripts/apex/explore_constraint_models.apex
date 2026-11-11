// Read-only: constraint models (CML) – where the model text lives, what is linked, and what the API can create.
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
for (String o : new List<String>{ 'ExpressionSetDefinition', 'ExpressionSetDefinitionVersion', 'ExpressionSet', 'ExpressionSetVersion',
        'ExpressionSetConstraintObj', 'ConstraintModel', 'ConstraintModelVersion', 'ExpressionSetVersionContent' }) {
    if (!gd.containsKey(o.toLowerCase())) { System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ': not available'); continue; }
    Schema.DescribeSObjectResult d = gd.get(o.toLowerCase()).getDescribe();
    List<String> fs = new List<String>();
    for (Schema.SObjectField sf : d.fields.getMap().values()) {
        Schema.DescribeFieldResult x = sf.getDescribe();
        String n = x.getName();
        if (x.isCustom() || n.endsWith('ById') || n == 'SystemModstamp' || n == 'IsDeleted' || n.endsWith('Date') && n.startsWith('Last')) continue;
        String t = String.valueOf(x.getType());
        if (x.getType() == Schema.DisplayType.PICKLIST) {
            List<String> v = new List<String>();
            for (Schema.PicklistEntry e : x.getPicklistValues()) v.add(e.getValue());
            t += '[' + String.join(v, '|') + ']';
        }
        fs.add(n + ':' + t + (x.isCreateable() ? ':C' : '') + (x.isUpdateable() ? ':U' : ''));
    }
    fs.sort();
    System.debug(LoggingLevel.ERROR, 'OBJECT ' + o + ' create=' + d.isCreateable() + ' update=' + d.isUpdateable() + ' | ' + String.join(fs, ', '));
}
// The org's constraint models
for (SObject es : Database.query('SELECT FIELDS(STANDARD) FROM ExpressionSet WHERE InterfaceSourceType = \'Constraint\' LIMIT 20')) {
    System.debug(LoggingLevel.ERROR, 'MODEL ' + es);
    for (SObject v : Database.query('SELECT FIELDS(STANDARD) FROM ExpressionSetVersion WHERE ExpressionSetId = \'' + es.Id + '\'')) {
        System.debug(LoggingLevel.ERROR, '  VERSION ' + v);
    }
    Map<String, Integer> byType = new Map<String, Integer>();
    List<String> sample = new List<String>();
    for (SObject c : Database.query('SELECT ConstraintModelTag, ConstraintModelTagType, ReferenceObject.Name, ReferenceObjectId FROM ExpressionSetConstraintObj WHERE ExpressionSetId = \'' + es.Id + '\' LIMIT 200')) {
        String t = (String) c.get('ConstraintModelTagType');
        byType.put(t, (byType.containsKey(t) ? byType.get(t) : 0) + 1);
        if (sample.size() < 8) sample.add(c.get('ConstraintModelTag') + '=' + c.get('ReferenceObjectId'));
    }
    System.debug(LoggingLevel.ERROR, '  LINKS ' + byType + ' e.g. ' + String.join(sample, ', '));
}
// Where is the CML text? Look for files attached to the model versions
for (SObject v : Database.query('SELECT Id, Name FROM ExpressionSetVersion WHERE ExpressionSet.InterfaceSourceType = \'Constraint\' LIMIT 5')) {
    for (ContentDocumentLink l : [SELECT ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.ContentSize FROM ContentDocumentLink WHERE LinkedEntityId = :v.Id]) {
        System.debug(LoggingLevel.ERROR, '  FILE on ' + v.get('Name') + ': ' + l.ContentDocument.Title + '.' + l.ContentDocument.FileExtension + ' ' + l.ContentDocument.ContentSize + ' bytes');
    }
}
