/** Spec 2.3 / 7A: root account and resolved payer across a four-level hierarchy, re-parenting, depth limit. */
@IsTest
private class AccountHierarchyServiceTest {

    static Account acc(String name, String level, String payer, Id parentId) {
        return new Account(Name = name, Account_Level__c = level, Payer_Type__c = payer, ParentId = parentId);
    }

    static Map<String, Account> load() {
        Map<String, Account> m = new Map<String, Account>();
        for (Account a : [SELECT Id, Name, Root_Account__c, Resolved_Payer__c FROM Account]) {
            m.put(a.Name, a);
        }
        return m;
    }

    /** The Pulse worked example from spec 7A. */
    @TestSetup
    static void pulse() {
        Account hq = acc('Pulse Fitness Brands', 'Corporate', 'Self-Pay', null);
        insert hq;
        Account west = acc('Pulse West', 'Region', 'Parent-Pay', hq.Id);
        insert west;
        Account irvine = acc('Pulse Irvine', 'Location', 'Parent-Pay', west.Id);
        Account coastal = acc('Coastal Fitness LLC', 'Franchisee', 'Self-Pay', west.Id);
        insert new List<Account>{ irvine, coastal };
        insert new List<Account>{
            acc('Pulse Santa Monica', 'Location', 'Parent-Pay', coastal.Id),
            acc('Pulse Venice', 'Location', 'Self-Pay', coastal.Id)
        };
    }

    @IsTest
    static void resolvesRootAndPayer() {
        // blank = this account (Salesforce does not allow an account lookup to its own record)
        Map<String, Account> m = load();
        Id hq = m.get('Pulse Fitness Brands').Id;
        Assert.isNull(m.get('Pulse Fitness Brands').Root_Account__c, 'the top account is the root');
        for (Account a : m.values()) {
            if (a.Id != hq) {
                Assert.areEqual(hq, a.Root_Account__c, a.Name + ' root');
            }
        }
        Assert.isNull(m.get('Pulse Fitness Brands').Resolved_Payer__c, 'HQ pays for itself');
        Assert.areEqual(hq, m.get('Pulse West').Resolved_Payer__c);
        Assert.areEqual(hq, m.get('Pulse Irvine').Resolved_Payer__c, 'pays two levels up');
        Assert.isNull(m.get('Coastal Fitness LLC').Resolved_Payer__c, 'Coastal pays for itself');
        Assert.areEqual(m.get('Coastal Fitness LLC').Id, m.get('Pulse Santa Monica').Resolved_Payer__c);
        Assert.isNull(m.get('Pulse Venice').Resolved_Payer__c, 'Venice pays for itself');
    }

    @IsTest
    static void payerChangeMovesBillingResponsibility() {
        Account venice = [SELECT Id FROM Account WHERE Name = 'Pulse Venice'];
        venice.Payer_Type__c = 'Parent-Pay';
        Test.startTest();
        update venice;
        Test.stopTest();
        Map<String, Account> m = load();
        Assert.areEqual(m.get('Coastal Fitness LLC').Id, m.get('Pulse Venice').Resolved_Payer__c, 'T12: now paid by its parent');
    }

    @IsTest
    static void reparentRecalculatesSubtree() {
        // Coastal becomes parent-pay: its parent-pay children now roll up to HQ
        Account coastal = [SELECT Id FROM Account WHERE Name = 'Coastal Fitness LLC'];
        coastal.Payer_Type__c = 'Parent-Pay';
        update coastal;
        Map<String, Account> m = load();
        Id hq = m.get('Pulse Fitness Brands').Id;
        Assert.areEqual(hq, m.get('Coastal Fitness LLC').Resolved_Payer__c);
        Assert.areEqual(hq, m.get('Pulse Santa Monica').Resolved_Payer__c);
        Assert.isNull(m.get('Pulse Venice').Resolved_Payer__c, 'self-pay stays its own payer');
    }

    @IsTest
    static void newHierarchyGetsItsOwnRoot() {
        Account other = acc('Halo Spa Collective', 'Corporate', 'Self-Pay', null);
        insert other;
        Account irvine = [SELECT Id FROM Account WHERE Name = 'Pulse Irvine'];
        irvine.ParentId = other.Id;
        update irvine;
        Map<String, Account> m = load();
        Assert.areEqual(other.Id, m.get('Pulse Irvine').Root_Account__c, 'moved to another hierarchy (LCM-16)');
        Assert.areEqual(other.Id, m.get('Pulse Irvine').Resolved_Payer__c, 'parent-pay: Halo HQ pays');
    }

    @IsTest
    static void fifthLevelIsBlocked() {
        Account venice = [SELECT Id FROM Account WHERE Name = 'Pulse Venice'];
        Account fifth = acc('Too Deep', 'Location', 'Parent-Pay', venice.Id);
        Database.SaveResult r = Database.insert(fifth, false);
        Assert.isFalse(r.isSuccess(), 'a fifth level must be blocked (US-01)');
    }

    @IsTest
    static void topAccountCannotBeParentPay() {
        Database.SaveResult r = Database.insert(acc('Orphan', 'Corporate', 'Parent-Pay', null), false);
        Assert.isFalse(r.isSuccess(), 'root must be self-pay (US-02)');
    }

    @IsTest
    static void locationCountFromCoreTierAssets() {
        Account hq = [SELECT Id FROM Account WHERE Name = 'Pulse Fitness Brands'];
        Account irvine = [SELECT Id FROM Account WHERE Name = 'Pulse Irvine'];
        Product2 tier = new Product2(Name = 'Starter', ProductCode = 'MB-STR', IsActive = true, Family = 'Recurring');
        insert tier;
        Test.startTest();
        insert new Asset(Name = 'Starter – Irvine', AccountId = irvine.Id, Product2Id = tier.Id, Quantity = 1);
        Test.stopTest();
        LocationCountService.recalculate(new Set<Id>{ hq.Id });
        Decimal n = [SELECT Active_Location_Count__c FROM Account WHERE Id = :hq.Id].Active_Location_Count__c;
        Assert.isTrue(n == 1, 'expected 1 active location, got ' + n);
    }
}
