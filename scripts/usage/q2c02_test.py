#!/usr/bin/env python3
"""CREATES test opportunities + quotes "MR103 Q2C02 ...": MR-119 final quote statuses at close (T1-T4)."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
upd = lambda s, i, v: json.loads(run(["sf", "data", "update", "record", "--sobject", s, "--record-id", i, "--values", v, "--target-org", "target", "--json"]))
def extra_quote(opp, name):
    place({"pricingPref": "Skip", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip", "graph": {"graphId": "x", "records": [
        {"referenceId": "q", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": name, "OpportunityId": opp, "Pricebook2Id": PB,
                                        "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": 12, "LegalEntityId": LE}}]}})
    return q(f"SELECT Id FROM Quote WHERE OpportunityId = '{opp}' AND Name = '{name}' LIMIT 1")[0]["Id"]
def setup(tag):
    q1 = case(f"Q2C02 {tag} synced", tag, 12, [("MB-ACC", "Term Monthly")], None)
    opp = q(f"SELECT OpportunityId FROM Quote WHERE Id = '{q1['Id']}'")[0]["OpportunityId"]
    upd("Quote", q1["Id"], "Status='Needs Review'"); time.sleep(3)   # auto-sync (MR-118)
    ids = {"synced": q1["Id"], "draft": extra_quote(opp, f"MR103 Q2C02 {tag} draft"), "review": extra_quote(opp, f"MR103 Q2C02 {tag} review"),
           "presented": extra_quote(opp, f"MR103 Q2C02 {tag} presented")}
    upd("Quote", ids["review"], "Status='In Review'"); upd("Quote", ids["presented"], "Status='Presented'")
    return opp, ids
st = lambda ids: {k: q(f"SELECT Status FROM Quote WHERE Id = '{v}'")[0]["Status"] for k, v in ids.items()}
# T3 first: synced quote Approved, not presented -> blocked
opp, ids = setup("T1")
upd("Quote", ids["synced"], "Status='Approved'")
r = upd("Opportunity", opp, "StageName='Closed Won'")
print("T3", "PASS" if r.get("status") != 0 and "present" in r.get("message", "").lower() else "FAIL", "|", r.get("message", "ok")[:160])
# T1: synced Presented -> Closed Won
upd("Quote", ids["synced"], "Status='Presented'")
r = upd("Opportunity", opp, "StageName='Closed Won'"); time.sleep(3); s = st(ids)
want = {"synced": "Accepted", "draft": "Voided", "review": "Voided", "presented": "Denied"}
print("T1", "PASS" if s == want else "FAIL", s, r.get("message", "")[:150])
# T4: edit a final quote
r = upd("Quote", ids["draft"], "Name='edited'")
print("T4", "PASS" if r.get("status") != 0 else "FAIL", "|", r.get("message", "")[:140])
# T2: Closed Lost
opp2, ids2 = setup("T2")
upd("Quote", ids2["synced"], "Status='Presented'")
upd("Opportunity", opp2, "StageName='Closed Lost'"); time.sleep(3); s = st(ids2)
want = {"synced": "Denied", "draft": "Voided", "review": "Voided", "presented": "Denied"}
print("T2", "PASS" if s == want else "FAIL", s)
