#!/usr/bin/env python3
"""CREATES test data "MR103 Q2C04 ...": MR-121 order auto-activation, contract, assets, co-term (T1, T4)."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
upd = lambda s, i, v: json.loads(run(["sf", "data", "update", "record", "--sobject", s, "--record-id", i, "--values", v, "--target-org", "target", "--json"]))
acc = q("SELECT Id FROM Account WHERE Name LIKE 'MR103 Q2C04%' LIMIT 1")
if acc: ACCT = acc[0]["Id"]
else:
    ACCT = json.loads(run(["sf", "data", "create", "record", "--sobject", "Account", "--values", f"Name='MR103 Q2C04 {STAMP}' BillingStreet='1 Test St' BillingCity='San Luis Obispo' BillingPostalCode='93401' BillingCountry='United States' ShippingStreet='1 Test St' ShippingCity='San Luis Obispo' ShippingPostalCode='93401' ShippingCountry='United States'", "--target-org", "target", "--json"])).get("result", {}).get("id")
    run(["sf", "data", "create", "record", "--sobject", "Contact", "--values", f"LastName='Billing' AccountId={ACCT} Email=billing@example.com", "--target-org", "target"])
print("account", ACCT)
def win(tag):
    qt = case(f"Q2C04 {tag}", tag, 36, [("MB-ULT", "Term Monthly")], None, account=ACCT)
    opp = q(f"SELECT OpportunityId FROM Quote WHERE Id = '{qt['Id']}'")[0]["OpportunityId"]
    upd("Quote", qt["Id"], "Status='Needs Review'"); time.sleep(3); upd("Quote", qt["Id"], "Status='Presented'")
    upd("Opportunity", opp, "StageName='Closed Won'")
    for _ in range(30):
        time.sleep(6)
        o = q(f"SELECT MB_Order__c, MB_Order_Error__c FROM Opportunity WHERE Id = '{opp}'")[0]
        if o["MB_Order__c"]:
            od = q(f"SELECT OrderNumber, Status, ContractId, MB_Activation_Error__c FROM Order WHERE Id = '{o['MB_Order__c']}'")[0]
            if od["Status"] == "Activated" or od["MB_Activation_Error__c"]: return od
        elif o["MB_Order_Error__c"]: return {"error": o["MB_Order_Error__c"]}
    return od if o["MB_Order__c"] else o
o1 = win("T1"); print("order 1:", {k: v for k, v in o1.items() if k != "attributes"})
cons = q(f"SELECT Id, Status, StartDate, EndDate, ContractTerm FROM Contract WHERE AccountId = '{ACCT}'")
assets = q(f"SELECT Name, LifecycleStartDate, LifecycleEndDate FROM Asset WHERE AccountId = '{ACCT}'")
print("contracts:", [{k: v for k, v in c.items() if k != "attributes"} for c in cons]); print("assets:", [(a["Name"], a["LifecycleEndDate"]) for a in assets])
print("T1", "PASS" if o1.get("Status") == "Activated" and len(cons) == 1 and cons[0]["Status"] == "Activated" and assets else "FAIL")
o2 = win("T4"); print("order 2:", {k: v for k, v in o2.items() if k != "attributes"})
cons2 = q(f"SELECT Id FROM Contract WHERE AccountId = '{ACCT}'")
print("T4", "PASS" if o2.get("Status") == "Activated" and len(cons2) == 1 and o2.get("ContractId") == cons[0]["Id"] else "FAIL", "| contracts:", len(cons2), "| assets:", len(q(f"SELECT Id FROM Asset WHERE AccountId = '{ACCT}'")))
