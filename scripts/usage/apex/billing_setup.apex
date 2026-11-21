// CHANGES org setup (idempotent): tax treatments per legal entity on the mock adapter (Default Tax Policy); AU billing treatments copied from UK
TaxTreatment us = [SELECT TaxPolicyId, TaxEngineId FROM TaxTreatment WHERE Name = 'Default Tax Policy' LIMIT 1];
Map<String, String> codes = new Map<String, String>{ 'Default Legal Entity - Canada' => 'GST', 'Default Legal Entity - EU' => 'VAT', 'Default Legal Entity - UK' => 'VAT', 'Default Legal Entity - AU' => 'GST' };
Set<Id> have = new Set<Id>();
for (TaxTreatment t : [SELECT LegalEntityId FROM TaxTreatment WHERE TaxPolicyId = :us.TaxPolicyId]) have.add(t.LegalEntityId);
for (LegalEntity le : [SELECT Id, Name FROM LegalEntity WHERE Name IN :codes.keySet()]) {
    if (have.contains(le.Id)) { System.debug(LoggingLevel.ERROR, 'tax treatment exists: ' + le.Name); continue; }
    TaxTreatment t = new TaxTreatment(Name = 'Tax - ' + le.Name.replace('Default Legal Entity - ', '') + ' ' + codes.get(le.Name), TaxPolicyId = us.TaxPolicyId,
        LegalEntityId = le.Id, TaxEngineId = us.TaxEngineId, TaxCode = codes.get(le.Name), IsTaxable = true, Status = 'Draft');
    insert t; t.Status = 'Active'; update t;
    System.debug(LoggingLevel.ERROR, 'tax treatment created: ' + t.Name);
}
LegalEntity au = [SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - AU' LIMIT 1];
if ([SELECT COUNT() FROM BillingTreatment WHERE LegalEntityId = :au.Id] == 0) {
    for (BillingTreatment src : [SELECT Id, Name, BillingPolicyId, Description FROM BillingTreatment WHERE Name LIKE 'Billing Treatment - UK - %']) {
        BillingTreatment bt = new BillingTreatment(Name = src.Name.replace('UK', 'AU'), BillingPolicyId = src.BillingPolicyId, LegalEntityId = au.Id, Description = src.Description, Status = 'Draft');
        insert bt;
        for (BillingTreatmentItem si : [SELECT Name, BillingType, ProcessingOrder, Percentage, FlatAmount FROM BillingTreatmentItem WHERE BillingTreatmentId = :src.Id]) {
            BillingTreatmentItem bi = si.clone(false, true); bi.Name = si.Name.replace('UK', 'AU'); bi.BillingTreatmentId = bt.Id; insert bi;
        }
        bt.Status = 'Active'; update bt;
        System.debug(LoggingLevel.ERROR, 'billing treatment created: ' + bt.Name);
    }
} else System.debug(LoggingLevel.ERROR, 'AU billing treatments exist');
