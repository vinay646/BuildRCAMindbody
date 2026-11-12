// Read-only: the pending usage journal, usage settings, and the jobs/actions that process usage
for (String o : new List<String>{ 'TransactionJournal', 'UsageEntitlementAccount', 'UsageEntitlementBucket', 'TransactionUsageEntitlement' }) {
    List<String> fs = new List<String>(Schema.getGlobalDescribe().get(o.toLowerCase()).getDescribe().fields.getMap().keySet());
    for (SObject r : Database.query('SELECT ' + String.join(fs, ',') + ' FROM ' + o + ' ORDER BY CreatedDate LIMIT 2')) {
        Map<String, Object> m = r.getPopulatedFieldsAsMap().clone();
        for (String k : new List<String>(m.keySet())) if (k.startsWith('Created') || k.startsWith('LastModified') || k == 'SystemModstamp' || k == 'IsDeleted' || k == 'OwnerId') m.remove(k);
        System.debug(LoggingLevel.ERROR, o.left(4).toUpperCase() + ' ' + JSON.serialize(m));
    }
}
for (AsyncApexJob j : [SELECT ApexClass.Name, JobType, Status, CreatedDate FROM AsyncApexJob WHERE CreatedDate = LAST_N_DAYS:5 ORDER BY CreatedDate DESC LIMIT 10]) System.debug(LoggingLevel.ERROR, 'JOB ' + j.ApexClass.Name + ' ' + j.JobType + ' ' + j.Status);
for (CronTrigger c : [SELECT CronJobDetail.Name, CronJobDetail.JobType, State, NextFireTime FROM CronTrigger LIMIT 30]) System.debug(LoggingLevel.ERROR, 'CRON ' + c.CronJobDetail.Name + ' | ' + c.CronJobDetail.JobType + ' | ' + c.State + ' | ' + c.NextFireTime);
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
for (String k : gd.keySet()) if (k.contains('usage') && (k.contains('setting') || k.contains('batch') || k.contains('job') || k.contains('rating'))) System.debug(LoggingLevel.ERROR, 'OBJNAME ' + k);
