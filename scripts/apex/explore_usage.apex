// Read-only: the pending usage journal, usage settings, and the jobs/actions that process usage
for (SObject r : Database.query('SELECT FIELDS(ALL) FROM TransactionJournal LIMIT 1')) System.debug(LoggingLevel.ERROR, 'TJ ' + JSON.serialize(r));
for (SObject r : Database.query('SELECT FIELDS(ALL) FROM UsageEntitlementAccount LIMIT 1')) System.debug(LoggingLevel.ERROR, 'UEA ' + JSON.serialize(r));
for (AsyncApexJob j : [SELECT ApexClass.Name, JobType, Status, CreatedDate FROM AsyncApexJob WHERE CreatedDate = LAST_N_DAYS:5 ORDER BY CreatedDate DESC LIMIT 10]) System.debug(LoggingLevel.ERROR, 'JOB ' + j.ApexClass.Name + ' ' + j.JobType + ' ' + j.Status);
for (CronTrigger c : [SELECT CronJobDetail.Name, CronJobDetail.JobType, State, NextFireTime FROM CronTrigger LIMIT 30]) System.debug(LoggingLevel.ERROR, 'CRON ' + c.CronJobDetail.Name + ' | ' + c.CronJobDetail.JobType + ' | ' + c.State + ' | ' + c.NextFireTime);
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
for (String k : gd.keySet()) if (k.contains('usage') && (k.contains('setting') || k.contains('batch') || k.contains('job') || k.contains('rating'))) System.debug(LoggingLevel.ERROR, 'OBJNAME ' + k);
