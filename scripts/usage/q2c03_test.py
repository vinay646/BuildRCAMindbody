#!/usr/bin/env python3
"""CREATES test opportunities/quotes/orders "MR103 Q2C03 ...": MR-120 Closed Won creates the order (T3, T4, T5, T6)."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
upd = lambda s, i, v: json.loads(run(["sf", "data", "update", "record", "--sobject", s, "--record-id", i, "--values", v, "--target-org", "target", "--json"]))
def won(tag, lines, qty_note=""):
    qt = case(f"Q2C03 {tag}", tag, 36, lines, None)
    opp = q(f"SELECT OpportunityId FROM Quote WHERE Id = '{qt['Id']}'")[0]["OpportunityId"]
    upd("Quote", qt["Id"], "Status='Needs Review'"); time.sleep(3); upd("Quote", qt["Id"], "Status='Presented'")
    return qt, opp
def wait_opp(opp):
    for _ in range(18):
        time.sleep(5)
        o = q(f"SELECT MB_Order__c, MB_Order_Error__c, MB_Bookings_ARR__c, MB_Bookings_MRR__c, MB_Bookings_One_Time__c FROM Opportunity WHERE Id = '{opp}'")[0]
        if o["MB_Order__c"] or o["MB_Order_Error__c"]: return o
    return o
qt, opp = won("T3", [("MB-ULT", "Term Monthly")])
print("lines:", q(f"SELECT Product2.ProductCode, Quantity, NetUnitPrice, LegalEntityId, BillingTreatmentId FROM QuoteLineItem WHERE QuoteId = '{qt['Id']}'"))
r = upd("Opportunity", opp, "StageName='Closed Won'"); print("closed won:", r.get("status"), r.get("message", "")[:200])
o = wait_opp(opp); print("opp:", {k: v for k, v in o.items() if k != "attributes"})
if o["MB_Order__c"]:
    od = q(f"SELECT OrderNumber, Status, AccountId, Pricebook2Id, CurrencyIsoCode, EffectiveDate, QuoteId, OpportunityId FROM Order WHERE Id = '{o['MB_Order__c']}'")[0]
    items = q(f"SELECT Product2.ProductCode, Quantity, UnitPrice, ServiceDate, EndDate, BillingFrequency2, LegalEntityId, BillingTreatmentId FROM OrderItem WHERE OrderId = '{o['MB_Order__c']}'")
    print("order:", {k: v for k, v in od.items() if k != "attributes"}); print("order items:", len(items), [(i["Product2"]["ProductCode"], i["Quantity"], i["UnitPrice"]) for i in items])
    print("T3", "PASS" if od["QuoteId"] == qt["Id"] and items and o["MB_Bookings_ARR__c"] else "FAIL")
    upd("Opportunity", opp, "Description='save again'"); time.sleep(20)
    print("T4", "PASS" if len(q(f"SELECT Id FROM Order WHERE QuoteId = '{qt['Id']}'")) == 1 else "FAIL", "(one order)")
    r = upd("Opportunity", opp, "StageName='Negotiation/Review'")
    print("T6", "PASS" if r.get("status") != 0 else "FAIL", "|", r.get("message", "")[:120])
else:
    print("T3 FAIL – no order")
# T5: a line without legal entity -> error + task, then fix + retry
qt5, opp5 = won("T5", [("MB-ACC", "Term Monthly")])
l5 = q(f"SELECT Id, LegalEntityId FROM QuoteLineItem WHERE QuoteId = '{qt5['Id']}' LIMIT 1")[0]
print("clear legal entity:", upd("QuoteLineItem", l5["Id"], "LegalEntityId=''").get("status"))
upd("Opportunity", opp5, "StageName='Closed Won'"); o = wait_opp(opp5)
tasks = q(f"SELECT Subject FROM Task WHERE WhatId = '{opp5}'")
print("T5 error:", o["MB_Order_Error__c"], "| task:", [t["Subject"] for t in tasks])
upd("QuoteLineItem", l5["Id"], f"LegalEntityId={l5['LegalEntityId']}"); upd("Opportunity", opp5, "MB_Retry_Order__c=true"); o = wait_opp(opp5)
print("T5", "PASS" if tasks and o["MB_Order__c"] else "FAIL", "(retry created order:", o["MB_Order__c"], ")")
