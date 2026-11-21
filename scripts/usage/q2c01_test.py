#!/usr/bin/env python3
"""CREATES test opportunity + 2 quotes "MR103 Q2C01 ..." : MR-118 auto-sync checks (T1, T2, T4)."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
def upd(sobj, rid, vals):
    return json.loads(run(["sf", "data", "update", "record", "--sobject", sobj, "--record-id", rid, "--values", vals, "--target-org", "target", "--json"]))
q1 = case("Q2C01 first quote", "T1", 36, [("MB-ULT", "Term Monthly")], None)
opp = q(f"SELECT OpportunityId FROM Quote WHERE Id = '{q1['Id']}'")[0]["OpportunityId"]
o = lambda: q(f"SELECT SyncedQuoteId, Amount, RLM_TermMonths__c, MB_Billing_Frequency__c, MB_MRR__c, MB_ARR__c FROM Opportunity WHERE Id = '{opp}'")[0]
print("before submit:", {k: v for k, v in o().items() if k != "attributes"})
print("submit q1:", upd("Quote", q1["Id"], "Status='Needs Review'").get("status"))
time.sleep(4); r = o()
print("after submit:", {k: v for k, v in r.items() if k != "attributes"}, "| lines on opp:", len(q(f"SELECT Id FROM OpportunityLineItem WHERE OpportunityId = '{opp}'")),
      "| post:", [f["Body"] for f in q(f"SELECT Body FROM FeedItem WHERE ParentId = '{opp}' ORDER BY CreatedDate DESC LIMIT 1")])
print("T1", "PASS" if r["SyncedQuoteId"] == q1["Id"] else "FAIL")
# T2: second quote on the same opportunity is not synced
recs = [{"referenceId": "q2", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": "MR103 Q2C01 second quote", "OpportunityId": opp,
         "Pricebook2Id": PB, "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": 12, "LegalEntityId": LE}}]
r2 = place({"pricingPref": "Skip", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip", "graph": {"graphId": "q2", "records": recs}})
q2 = q(f"SELECT Id FROM Quote WHERE OpportunityId = '{opp}' AND Id != '{q1['Id']}' LIMIT 1")[0]["Id"]
upd("Quote", q2, "Status='Needs Review'"); time.sleep(3)
print("T2", "PASS" if o()["SyncedQuoteId"] == q1["Id"] else "FAIL", "(second quote not synced)")
# T4: term change on the synced quote reaches the opportunity
upd("Quote", q1["Id"], "RLM_TermMonths__c=24 MB_Billing_Frequency__c=Annual"); time.sleep(3); r = o()
print("T4", "PASS" if r["RLM_TermMonths__c"] == 24 and r["MB_Billing_Frequency__c"] == "Annual" else "FAIL", {k: v for k, v in r.items() if k != "attributes"})
