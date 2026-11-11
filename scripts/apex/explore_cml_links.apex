// Read-only: how the active QuantumBit Bundle model links CML types/ports to products and components.
for (SObject c : [SELECT ConstraintModelTag, ConstraintModelTagType, ReferenceObjectId FROM ExpressionSetConstraintObj
        WHERE ExpressionSet.ApiName = 'QuantumBitBundle' ORDER BY ConstraintModelTagType, ConstraintModelTag LIMIT 80]) {
    Id ref = (Id) c.get('ReferenceObjectId');
    String what = String.valueOf(ref.getSObjectType());
    if (what == 'Product2') {
        Product2 p = [SELECT ProductCode, Name, Type FROM Product2 WHERE Id = :ref];
        what += ' ' + p.ProductCode + ' "' + p.Name + '" type=' + p.Type;
    } else if (what == 'ProductRelatedComponent') {
        SObject r = Database.query('SELECT ParentProduct.ProductCode, ChildProduct.ProductCode, ProductComponentGroup.Name FROM ProductRelatedComponent WHERE Id = :ref');
        what += ' ' + r.getSObject('ParentProduct').get('ProductCode') + ' -> ' + (r.getSObject('ChildProduct') == null ? '(group)' : r.getSObject('ChildProduct').get('ProductCode'))
            + ' [' + (r.getSObject('ProductComponentGroup') == null ? '' : r.getSObject('ProductComponentGroup').get('Name')) + ']';
    }
    System.debug(LoggingLevel.ERROR, 'LINK ' + c.get('ConstraintModelTagType') + ' ' + c.get('ConstraintModelTag') + ' = ' + what);
}
