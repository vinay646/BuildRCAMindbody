#!/usr/bin/env python3
"""CREATES test quotes "CML TEST banner ..." saved with configuration rules running (as the quote line editor does), so
the Mindbody Plans messages show in the Quote Lines tab banner. Prints each quote number and what the save returned."""
import json, os, subprocess, time
from datetime import date, timedelta
API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"; TODAY = date.today()


def run(a):
    r = subprocess.run(a, capture_output=True, text=True); return r.stdout or r.stderr


def q(s):
    try:
        return json.loads(run(["sf", "data", "query", "--query", s, "--target-org", "target", "--json"]))["result"]["records"]
    except Exception:
        return []


def rest(path, body):
    out = run(["sf", "api", "request", "rest", API + path, "--method", "POST", "--body", json.dumps(body), "--target-org", "target"])
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:800]}


PB = q("SELECT Pricebook2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ACC' AND CurrencyIsoCode = 'USD' AND IsActive = true "
       "AND Pricebook2.IsStandard = false AND Pricebook2.IsActive = true LIMIT 1")[0]["Pricebook2Id"]
CONF = {"configurationMethod": "System", "configurationOptions": {"executeConfigurationRules": True, "addDefaultConfiguration": True,
                                                                  "validateProductCatalog": False, "validateAmendRenewCancel": False}}


def plan_quote(name, code, qvals):
    e = [x for x in q(f"SELECT Id, Product2Id, ProductSellingModel.SellingModelType FROM PricebookEntry WHERE Product2.ProductCode = '{code}' "
                      f"AND Pricebook2Id = '{PB}' AND CurrencyIsoCode = 'USD' AND IsActive = true") if (x.get("ProductSellingModel") or {}).get("SellingModelType") == "TermDefined"][0]
    body = {"pricingPref": os.environ.get("PRICING", "Skip"), "catalogRatesPref": "Skip", "taxPref": "Skip", "configurationPref": CONF, "graph": {"graphId": "b", "records": [
        {"referenceId": "q", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"CML TEST banner {name}", "Pricebook2Id": PB,
                                        "RLM_TermMonths__c": 12, **qvals}},
        {"referenceId": "l1", "record": {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q.id}", "Product2Id": e["Product2Id"],
                                         "PricebookEntryId": e["Id"], "Quantity": 1, "StartDate": str(TODAY), "EndDate": str(TODAY + timedelta(days=364)),
                                         "BillingFrequency": "Monthly", "PeriodBoundary": "Anniversary"}}]}}
    r = rest("/connect/rev/sales-transaction/actions/place", body)
    qid = r.get("salesTransactionId")
    print(f"\n== {name}: success {r.get('isSuccess')} errors {json.dumps(r.get('errorResponse'))[:400]}")
    if qid:
        time.sleep(5)
        qn = q(f"SELECT QuoteNumber FROM Quote WHERE Id = '{qid}'")[0]["QuoteNumber"]
        lines = q(f"SELECT Product2.ProductCode FROM QuoteLineItem WHERE QuoteId = '{qid}'")
        print(f"   quote {qn} ({qid}) lines {len(lines)}: {[l['Product2']['ProductCode'] for l in lines]}")
        extra = {k: v for k, v in r.items() if k not in ("isSuccess", "errorResponse", "salesTransactionId", "contextDetails")}
        if extra:
            print("   other response:", json.dumps(extra)[:600])


plan_quote("competitor prior system", "MB-ACC", {"Prior_system__c": "Vagaro"})
plan_quote("30 locations", "MB-ACC", {"Location_count__c": 30})
plan_quote("12 locations", "MB-ACC", {"Location_count__c": 12})
