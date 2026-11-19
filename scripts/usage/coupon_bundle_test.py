#!/usr/bin/env python3
"""CREATES test quotes "COUPON-BUNDLE ...": Accelerate added as a bundle (configurator adds its default components, like the
line editor), then the Coupon Code is set and the automatic reprice runs. Checks the lines survive and the discount applies."""
import json, os, subprocess, time
from datetime import date, timedelta

API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"
TODAY = date.today(); STAMP = time.strftime("%m%d-%H%M")


def run(a):
    return subprocess.run(a, capture_output=True, text=True).stdout


def q(soql):
    out = run(["sf", "data", "query", "--query", soql, "--target-org", "target", "--json"])
    try:
        return json.loads(out)["result"]["records"]
    except Exception:
        print("   query error:", out[:300]); return []


def place(body):
    out = run(["sf", "api", "request", "rest", API + "/connect/rev/sales-transaction/actions/place", "--method", "POST",
               "--body", json.dumps(body), "--target-org", "target"])
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:400]}


PB = q("SELECT Pricebook2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ULT' AND CurrencyIsoCode = 'USD' AND IsActive = true "
       "AND Pricebook2.IsStandard = false AND Pricebook2.IsActive = true AND (NOT Pricebook2.Name LIKE '%Floor%') LIMIT 1")[0]["Pricebook2Id"]
LE = q("SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - US' LIMIT 1")[0]["Id"]
ACC = q("SELECT Id FROM Account WHERE Root_Account__c = null AND (Active_Location_Count__c = null OR Active_Location_Count__c = 0) "
        "AND Id NOT IN (SELECT AccountId FROM Asset) AND (NOT Name LIKE 'QUAL-TEST%') ORDER BY CreatedDate DESC LIMIT 1")[0]["Id"]
e = q(f"SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ACC' AND Pricebook2Id = '{PB}' AND CurrencyIsoCode = 'USD' "
      f"AND IsActive = true AND ProductSellingModel.Name = 'Term Monthly'")[0]

opp = json.loads(run(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values",
                      f"Name='COUPON-BUNDLE {STAMP}' AccountId={ACC} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={PB} CurrencyIsoCode=USD",
                      "--target-org", "target", "--json"]))["result"]["id"]
r = place({"pricingPref": "System", "catalogRatesPref": "Skip", "taxPref": "Skip",
           "configurationPref": {"configurationMethod": "System", "configurationOptions": {"addDefaultConfiguration": True, "executeConfigurationRules": True,
                                                                                         "validateProductCatalog": True, "validateAmendRenewCancel": True}},
           "graph": {"graphId": "all", "records": [
               {"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": "COUPON-BUNDLE Accelerate", "OpportunityId": opp,
                                                "Pricebook2Id": PB, "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": 12, "LegalEntityId": LE}},
               {"referenceId": "l0", "record": {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q1.id}", "Product2Id": e["Product2Id"],
                                                "PricebookEntryId": e["Id"], "Quantity": 1, "StartDate": TODAY.isoformat(), "LegalEntityId": LE,
                                                "BillingFrequency": "Monthly", "EndDate": (TODAY + timedelta(days=364)).isoformat(), "PeriodBoundary": "Anniversary"}}]}})
print("place with configuration:", "ok" if r.get("isSuccess") else json.dumps(r.get("errorResponse") or r)[:500])
time.sleep(6)
qt = q(f"SELECT Id, QuoteNumber FROM Quote WHERE OpportunityId = '{opp}'")[0]
lines = lambda: q(f"SELECT Product2.ProductCode, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '{qt['Id']}' ORDER BY Product2.ProductCode")
fmt = lambda ls: [(x["Product2"]["ProductCode"], x["NetUnitPrice"]) for x in ls]
before = lines()
print(f"quote {qt['QuoteNumber']}: {len(before)} lines after create {fmt(before)}")
out = json.loads(run(["sf", "data", "update", "record", "--sobject", "Quote", "--record-id", qt["Id"], "--values", "Coupon_Code__c='NEWPROMO5'",
                      "--target-org", "target", "--json"]))
print("set Coupon Code NEWPROMO5:", "ok" if out.get("status") == 0 else out.get("message"))
for s in (10, 20, 30, 45, 60):
    time.sleep(s - (0 if s == 10 else [10, 20, 30, 45, 60][[10, 20, 30, 45, 60].index(s) - 1]))
    now = lines()
    acc = next((x["NetUnitPrice"] for x in now if x["Product2"]["ProductCode"] == "MB-ACC"), None)
    print(f"  after {s}s: {len(now)} lines, Accelerate net {acc}")
    if len(now) != len(before) or acc == 134.5:
        break
now = lines()
res = "PASS" if len(now) == len(before) and any(x["Product2"]["ProductCode"] == "MB-ACC" and x["NetUnitPrice"] == 134.5 for x in now) else "FAIL"
print(f"{res}: lines kept {len(now)}/{len(before)}, Accelerate discounted: {any(x['Product2']['ProductCode'] == 'MB-ACC' and x['NetUnitPrice'] == 134.5 for x in now)}")
