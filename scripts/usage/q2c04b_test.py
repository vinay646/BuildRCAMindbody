#!/usr/bin/env python3
"""CREATES test data "MR103 Q2C04 ...": MR-121 routing / asset types (T7-style) and missing-data case (T2)."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
upd = lambda s, i, v: json.loads(run(["sf", "data", "update", "record", "--sobject", s, "--record-id", i, "--values", v, "--target-org", "target", "--json"]))
def win(tag, lines, acct):
    qt = case(f"Q2C04 {tag}", tag, 36, lines, None, account=acct)
    if not qt: return None
    opp = q(f"SELECT OpportunityId FROM Quote WHERE Id = '{qt['Id']}'")[0]["OpportunityId"]
    upd("Quote", qt["Id"], "Status='Needs Review'"); time.sleep(3); upd("Quote", qt["Id"], "Status='Presented'")
    r = upd("Opportunity", opp, "StageName='Closed Won'")
    if r.get("status") != 0: print("won failed:", r.get("message")); return None
    for _ in range(30):
        time.sleep(6)
        o = q(f"SELECT MB_Order__c, MB_Order_Error__c FROM Opportunity WHERE Id = '{opp}'")[0]
        if o["MB_Order__c"]:
            od = q(f"SELECT Id, OrderNumber, Status, MB_Activation_Error__c FROM Order WHERE Id = '{o['MB_Order__c']}'")[0]
            if od["Status"] == "Activated" or od["MB_Activation_Error__c"]: return od
        elif o["MB_Order_Error__c"]: return {"error": o["MB_Order_Error__c"]}
    return {"timeout": o}
acc = q("SELECT Id FROM Account WHERE Name LIKE 'MR103 Q2C04 1%' ORDER BY CreatedDate LIMIT 1")[0]["Id"]
od = win("T7 routing", [("MB-ULT", "Term Monthly"), ("MB-IMP", None)], acc)
print("order:", od)
if od and od.get("Id"):
    items = q(f"SELECT Product2.ProductCode, MB_Fulfilment_Route__c FROM OrderItem WHERE OrderId = '{od['Id']}' AND Product2.ProductCode IN ('MB-ULT','MB-IMP')")
    print("routes:", [(i["Product2"]["ProductCode"], i["MB_Fulfilment_Route__c"]) for i in items])
    time.sleep(20)
    assets = q(f"SELECT Name, Product2.ProductCode, RenewalTerm FROM Asset WHERE AccountId = '{acc}' AND CreatedDate = TODAY AND Product2.ProductCode IN ('MB-ULT','MB-IMP') ORDER BY CreatedDate DESC LIMIT 2")
    print("assets:", [(a["Product2"]["ProductCode"], a["RenewalTerm"]) for a in assets])
    ok = od["Status"] == "Activated" and dict((i["Product2"]["ProductCode"], i["MB_Fulfilment_Route__c"]) for i in items) == {"MB-ULT": "Provisioning", "MB-IMP": "Services"}
    print("T7", "PASS" if ok else "FAIL")
# T2: account without contact or address
a2 = json.loads(run(["sf", "data", "create", "record", "--sobject", "Account", "--values", f"Name='MR103 Q2C04 T2 {STAMP}'", "--target-org", "target", "--json"])).get("result", {}).get("id")
od2 = win("T2 missing data", [("MB-ACC", "Term Monthly")], a2)
tasks = q(f"SELECT Subject FROM Task WHERE WhatId = '{od2.get('Id')}'") if od2 and od2.get("Id") else []
print("order:", od2, "| tasks:", [t["Subject"] for t in tasks])
print("T2", "PASS" if od2 and od2.get("Status") == "Draft" and od2.get("MB_Activation_Error__c") and tasks else "FAIL")
