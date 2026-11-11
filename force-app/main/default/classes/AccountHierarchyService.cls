/**
 * Keeps the account hierarchy fields right (spec 2.3, US-01, US-02, LCM-16, RLP-12).
 *
 *  Root_Account__c    the top (corporate) account of the hierarchy; blank on the top account itself.
 *  Resolved_Payer__c  the account that pays: blank when the account pays for itself (Self-Pay), else the
 *                     nearest Self-Pay ancestor (parent, grandparent or great-grandparent).
 * Blank means "this account" because Salesforce does not let an account lookup point at its own record
 * (CIRCULAR_DEPENDENCY, hierarchy constraint).
 *
 * Runs after insert and after a change of ParentId or Payer_Type__c, and recalculates the changed
 * accounts and everything below them (at most four levels, so three levels of descendants).
 * Also blocks a re-parent that would push any descendant below level four.
 */
public without sharing class AccountHierarchyService {

    public static final Integer MAX_DEPTH = 4;
    public static final String SELF_PAY = 'Self-Pay';
    public static final String PARENT_PAY = 'Parent-Pay';

    @TestVisible static Boolean running = false;

    public static void afterInsert(List<Account> accounts) {
        recalculate(idsOf(accounts), null);
    }

    public static void afterUpdate(List<Account> accounts, Map<Id, Account> oldMap) {
        Set<Id> changed = new Set<Id>();
        Map<Id, Account> reparented = new Map<Id, Account>();
        for (Account a : accounts) {
            Account old = oldMap.get(a.Id);
            if (a.ParentId != old.ParentId) {
                changed.add(a.Id);
                reparented.put(a.Id, a);
            } else if (a.Payer_Type__c != old.Payer_Type__c) {
                changed.add(a.Id);
            }
        }
        if (!changed.isEmpty()) {
            recalculate(changed, reparented);
        }
    }

    /** Recalculates root and payer for the given accounts and all their descendants. */
    public static void recalculate(Set<Id> accountIds, Map<Id, Account> reparented) {
        if (running || accountIds == null || accountIds.isEmpty()) {
            return;
        }
        running = true;
        try {
            Map<Id, Account> scope = loadWithAncestors(subtreeIds(accountIds));
            if (reparented != null && !reparented.isEmpty()) {
                blockTooDeep(scope, reparented);
            }
            List<Account> updates = new List<Account>();
            for (Account a : scope.values()) {
                Id root = rootOf(a);
                Id payer = payerOf(a);
                if (a.Root_Account__c != root || a.Resolved_Payer__c != payer) {
                    updates.add(new Account(Id = a.Id, Root_Account__c = root, Resolved_Payer__c = payer));
                }
            }
            if (!updates.isEmpty()) {
                update updates;
            }
        } finally {
            running = false;
        }
    }

    // ------------------------------------------------------------------ helpers

    static Set<Id> idsOf(List<Account> accounts) {
        Set<Id> ids = new Set<Id>();
        for (Account a : accounts) {
            ids.add(a.Id);
        }
        return ids;
    }

    /** The accounts plus every descendant (up to three levels below). */
    static Set<Id> subtreeIds(Set<Id> ids) {
        Set<Id> all = new Set<Id>(ids);
        for (Account d : [
            SELECT Id FROM Account
            WHERE ParentId IN :ids OR Parent.ParentId IN :ids OR Parent.Parent.ParentId IN :ids
        ]) {
            all.add(d.Id);
        }
        return all;
    }

    static Map<Id, Account> loadWithAncestors(Set<Id> ids) {
        return new Map<Id, Account>([
            SELECT Id, Name, ParentId, Payer_Type__c, Root_Account__c, Resolved_Payer__c,
                   Parent.Id, Parent.ParentId, Parent.Payer_Type__c,
                   Parent.Parent.Id, Parent.Parent.ParentId, Parent.Parent.Payer_Type__c,
                   Parent.Parent.Parent.Id, Parent.Parent.Parent.ParentId, Parent.Parent.Parent.Payer_Type__c
            FROM Account WHERE Id IN :ids
        ]);
    }

    /** The chain from the account up to its top-most loaded ancestor: [self, parent, grandparent, ...]. */
    @TestVisible
    static List<Account> chain(Account a) {
        List<Account> c = new List<Account>{ a };
        Account cur = a;
        for (Integer i = 1; i < MAX_DEPTH && cur.ParentId != null; i++) {
            cur = cur.Parent;
            if (cur == null) {
                break;
            }
            c.add(cur);
        }
        return c;
    }

    static Id rootOf(Account a) {
        List<Account> c = chain(a);
        Id root = c[c.size() - 1].Id;
        return root == a.Id ? null : root;   // the top account has no Root Account (it is the root)
    }

    static Id payerOf(Account a) {
        for (Account step : chain(a)) {
            if (step.Payer_Type__c != PARENT_PAY) {   // Self-Pay, or blank (treated as self-pay)
                return step.Id == a.Id ? null : step.Id;   // blank = pays for itself
            }
        }
        return null;   // no self-pay ancestor: the root validation rule prevents this
    }

    /** A moved account's subtree must still fit within four levels. */
    static void blockTooDeep(Map<Id, Account> scope, Map<Id, Account> reparented) {
        for (Account a : scope.values()) {
            List<Account> c = chain(a);
            if (c.size() == MAX_DEPTH && c[MAX_DEPTH - 1].ParentId != null) {
                for (Account moved : reparented.values()) {
                    moved.addError('Moving this account would put ' + a.Name
                        + ' below level four. A hierarchy is at most four levels (corporate, region, franchisee, location).');
                }
                return;
            }
        }
    }
}
