/**
 * RLP-01: Active_Location_Count__c on the root account = active core-tier locations across the whole
 * hierarchy. An active location is an asset for a core tier (Starter, Accelerate, Ultimate, Enterprise)
 * whose lifecycle has not ended; the asset quantity is the number of locations it covers, so both
 * quoting styles in CFG-04 (one line group per location, or one line with quantity) count the same.
 *
 * RLP-13: never recalculated synchronously inside the record trigger; the Asset trigger queues this
 * job, and LocationCountService.recalculateAll() can be scheduled nightly as a safety net.
 */
public without sharing class LocationCountService implements Queueable, Schedulable {

    public static final Set<String> CORE_TIERS = new Set<String>{ 'MB-STR', 'MB-ACC', 'MB-ULT', 'MB-ENT' };

    public static final List<String> INACTIVE_STATUSES = new List<String>{ 'Cancelled', 'Inactive', 'Obsolete' };

    private final Set<Id> rootIds;

    public LocationCountService(Set<Id> rootIds) {
        this.rootIds = rootIds;
    }

    public void execute(QueueableContext ctx) {
        recalculate(rootIds);
    }

    /** Schedulable entry point: recalculates every hierarchy (nightly safety net). */
    public void execute(SchedulableContext ctx) {
        recalculateAll();
    }

    public static void recalculateAll() {
        Set<Id> roots = new Set<Id>();
        for (AggregateResult r : [
            SELECT Root_Account__c root FROM Account WHERE Root_Account__c != null GROUP BY Root_Account__c LIMIT 2000
        ]) {
            roots.add((Id) r.get('root'));
        }
        recalculate(roots);
    }

    /** Recalculates the count on the given root accounts. */
    public static void recalculate(Set<Id> roots) {
        if (roots == null || roots.isEmpty()) {
            return;
        }
        Map<Id, Decimal> counts = new Map<Id, Decimal>();
        for (Id r : roots) {
            counts.put(r, 0);
        }
        // ARM keeps the live quantity in CurrentQuantity once the asset is managed by an order;
        // assets created another way may only carry Quantity, so both are summed and the ARM one wins.
        Map<String, Schema.SObjectField> f = Schema.SObjectType.Asset.fields.getMap();
        Boolean hasCurrent = f.containsKey('currentquantity');
        String soql = 'SELECT Account.Root_Account__c root, SUM(Quantity) qty'
            + (hasCurrent ? ', SUM(CurrentQuantity) cur' : '') + ' FROM Asset'
            + ' WHERE Account.Root_Account__c IN :roots AND Product2.ProductCode IN :tiers'
            + (f.containsKey('lifecycleenddate') ? ' AND (LifecycleEndDate = null OR LifecycleEndDate >= TODAY)' : '')
            + ' AND (Status = null OR Status NOT IN :inactive)'
            + ' GROUP BY Account.Root_Account__c';
        Map<String, Object> binds = new Map<String, Object>{
            'roots' => roots, 'tiers' => CORE_TIERS, 'inactive' => INACTIVE_STATUSES
        };
        for (AggregateResult r : (List<AggregateResult>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            Decimal cur = hasCurrent ? (Decimal) r.get('cur') : null;
            Decimal q = (cur != null && cur > 0) ? cur : (Decimal) r.get('qty');
            counts.put((Id) r.get('root'), q == null ? 0 : q);
        }
        List<Account> updates = new List<Account>();
        for (Account a : [SELECT Id, Active_Location_Count__c FROM Account WHERE Id IN :roots]) {
            Decimal c = counts.get(a.Id);
            if (a.Active_Location_Count__c != c) {
                updates.add(new Account(Id = a.Id, Active_Location_Count__c = c));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    /** Called from the Asset trigger: queue a recount for the hierarchies the assets belong to. */
    public static void assetsChanged(List<Asset> assets) {
        Set<Id> accountIds = new Set<Id>();
        for (Asset a : assets) {
            if (a.AccountId != null) {
                accountIds.add(a.AccountId);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }
        Set<Id> roots = new Set<Id>();
        for (Account a : [SELECT Root_Account__c FROM Account WHERE Id IN :accountIds AND Root_Account__c != null]) {
            roots.add(a.Root_Account__c);
        }
        if (roots.isEmpty()) {
            return;
        }
        if (System.isBatch() || System.isFuture() || System.isQueueable()
                || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            recalculate(roots);   // already async, or no queueable slot left
        } else {
            System.enqueueJob(new LocationCountService(roots));
        }
    }
}
