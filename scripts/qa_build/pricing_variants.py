#!/usr/bin/env python3
"""CREATES test quotes "CML TEST pricing ..." to find which blank inputs make QA pricing fail with
"Duplicate entries found while looking up VolumeDiscount"."""
import json, os, subprocess, time
from datetime import date, timedelta
API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"; TODAY = date.today()
run = lambda a: (lambda r: r.stdout or r.stderr)(subprocess.run(a, capture_output=True, text=True))


def q(s):
    try:
        return json.loads(run(["sf", "data", "query", "--query", s, "--target-org", "target", "--json"]))["result"]["records"]
    except Exception:
        return []


qli = json.loads(run(["sf", "sobject", "describe", "--sobject", "QuoteLineItem", "--target-org", "target", "--json"]))["result"]["fields"]
print("QLI fields with location/billing/frequency:", [f["name"] for f in qli if any(k in f["name"].lower() for k in ("location", "billing_freq", "frequency_value"))])
PB = q("SELECT Pricebook2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ACC' AND CurrencyIsoCode = 'USD' AND IsActive = true "
       "AND Pricebook2.IsStandard = false AND Pricebook2.IsActive = true LIMIT 1")[0]["Pricebook2Id"]
E = [x for x in q(f"SELECT Id, Product2Id, ProductSellingModel.SellingModelType FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ACC' AND Pricebook2Id = '{PB}' "
                  f"AND CurrencyIsoCode = 'USD' AND IsActive = true") if x["ProductSellingModel"]["SellingModelType"] == "TermDefined"][0]
loc_field = next((f["name"] for f in qli if f["name"].lower() in ("location_count__c", "locationcount__c")), None)


def try_(name, line_extra, quote_extra):
    body = {"pricingPref": "System", "catalogRatesPref": "Skip", "taxPref": "Skip", "configurationPref": {"configurationMethod": "Skip"},
            "graph": {"graphId": "p", "records": [
                {"referenceId": "q", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"CML TEST pricing {name}", "Pricebook2Id": PB,
                                                "RLM_TermMonths__c": 12, **quote_extra}},
                {"referenceId": "l1", "record": {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q.id}", "Product2Id": E["Product2Id"],
                                                 "PricebookEntryId": E["Id"], "Quantity": 1, "StartDate": str(TODAY), "EndDate": str(TODAY + timedelta(days=364)),
                                                 "BillingFrequency": "Monthly", "PeriodBoundary": "Anniversary", **line_extra}}]}}
    out = run(["sf", "api", "request", "rest", API + "/connect/rev/sales-transaction/actions/place", "--method", "POST", "--body", json.dumps(body), "--target-org", "target"])
    try:
        r = json.loads(out)
    except Exception:
        r = {"raw": out[:300]}
    res = "OK" if r.get("isSuccess") else json.dumps(r.get("errorResponse") or r)[:250]
    net = ""
    if r.get("isSuccess"):
        time.sleep(3)
        l = q(f"SELECT ListPrice, NetUnitPrice, Billing_Frequency_Value__c FROM QuoteLineItem WHERE QuoteId = '{r['salesTransactionId']}' AND Product2.ProductCode = 'MB-ACC'")
        net = json.dumps([{k: v for k, v in x.items() if k != 'attributes'} for x in l])
    print(f"== {name}: {res} {net}")


try_("blank inputs", {}, {})
try_("billing value 1", {"Billing_Frequency_Value__c": 1}, {})
try_("billing value 12", {"Billing_Frequency_Value__c": 12}, {})
if loc_field:
    try_("billing 1 + line location 1", {"Billing_Frequency_Value__c": 1, loc_field: 1}, {"Location_count__c": 1})
    try_("billing 1 + line location 20", {"Billing_Frequency_Value__c": 1, loc_field: 20}, {"Location_count__c": 20})
try_("billing 1 + quote location 20", {"Billing_Frequency_Value__c": 1}, {"Location_count__c": 20})
