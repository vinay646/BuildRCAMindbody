#!/usr/bin/env python3
"""CREATES test quotes "COUPON-PROBE2 ...". Coupon via a placeholder line price adjustment inserted after the line exists,
then a reprice; ineligible product; removing the coupon; flow-callable actions that reprice."""
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


def rest(method, path, body=None):
    a = ["sf", "api", "request", "rest", API + path, "--method", method, "--target-org", "target"]
    if body is not None:
        a += ["--body", json.dumps(body)]
    out = run(a)
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:400]}


def place(body):
    return rest("POST", "/connect/rev/sales-transaction/actions/place", body)


acts = rest("GET", "/actions/standard")
names = [a["name"] for a in (acts.get("actions") or [])]
print("== standard actions (sales transaction / pricing / quote):", [n for n in names if any(k in n.lower() for k in ("place", "pric", "salestrans", "quote", "promo"))])

PB = q("SELECT Pricebook2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ULT' AND CurrencyIsoCode = 'USD' AND IsActive = true "
       "AND Pricebook2.IsStandard = false AND Pricebook2.IsActive = true AND (NOT Pricebook2.Name LIKE '%Floor%') LIMIT 1")[0]["Pricebook2Id"]
LE = q("SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - US' LIMIT 1")[0]["Id"]
ACC = q("SELECT Id FROM Account WHERE Root_Account__c = null AND (Active_Location_Count__c = null OR Active_Location_Count__c = 0) "
        "AND Id NOT IN (SELECT AccountId FROM Asset) AND (NOT Name LIKE 'QUAL-TEST%') ORDER BY CreatedDate DESC LIMIT 1")[0]["Id"]


def quote_with(code):
    e = q(f"SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = '{code}' AND Pricebook2Id = '{PB}' AND CurrencyIsoCode = 'USD' "
          f"AND IsActive = true AND ProductSellingModel.Name = 'Term Monthly'")[0]
    opp = json.loads(run(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values",
                          f"Name='COUPON-PROBE2 {STAMP}' AccountId={ACC} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={PB} CurrencyIsoCode=USD",
                          "--target-org", "target", "--json"]))["result"]["id"]
    r = place({"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "all", "records": [
                   {"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"COUPON-PROBE2 {code}", "OpportunityId": opp,
                                                    "Pricebook2Id": PB, "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": 12, "LegalEntityId": LE}},
                   {"referenceId": "l0", "record": {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q1.id}", "Product2Id": e["Product2Id"],
                                                    "PricebookEntryId": e["Id"], "Quantity": 1, "StartDate": TODAY.isoformat(), "LegalEntityId": LE,
                                                    "BillingFrequency": "Monthly", "EndDate": (TODAY + timedelta(days=364)).isoformat(), "PeriodBoundary": "Anniversary"}}]}})
    if r.get("isSuccess") is not True:
        print("   place failed", json.dumps(r)[:300]); return None, None
    time.sleep(6)
    qt = q(f"SELECT Id, QuoteNumber FROM Quote WHERE OpportunityId = '{opp}'")[0]
    ln = q(f"SELECT Id FROM QuoteLineItem WHERE QuoteId = '{qt['Id']}'")[0]
    return qt, ln["Id"]


def reprice(qid):
    r = place({"pricingPref": "Force", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "upd", "records": [{"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "PATCH", "id": qid},
                                                                                       "Description": "reprice " + time.strftime("%H:%M:%S")}}]}})
    time.sleep(6)
    return "ok" if r.get("isSuccess") else json.dumps(r.get("errorResponse") or r)[:300]


def show(label, lid):
    ln = q(f"SELECT ListPrice, NetUnitPrice FROM QuoteLineItem WHERE Id = '{lid}'")[0]
    adj = q(f"SELECT Id, AdjustmentSource, AdjustmentValue, CouponCode, PriceAdjustmentCauseId FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = '{lid}'")
    print(f"   {label}: list {ln['ListPrice']} net {ln['NetUnitPrice']} | adjustments {[{k: v for k, v in a.items() if k != 'attributes'} for a in adj]}")
    return adj


def insert_placeholder(lid, coupon):
    r = json.loads(run(["sf", "data", "create", "record", "--sobject", "QuoteLinePriceAdjustment", "--values",
                        f"QuoteLineItemId={lid} AdjustmentSource=Promotion AdjustmentType=AdjustmentPercentage AdjustmentValue=0 CouponCode={coupon}",
                        "--target-org", "target", "--json"]))
    print("   insert placeholder (DML):", "ok" if r.get("status") == 0 else r.get("message"))


print("\n===== A. Accelerate: placeholder inserted by DML after the line exists, then reprice")
qt, lid = quote_with("MB-ACC")
if lid:
    print("   quote", qt["QuoteNumber"]); show("before", lid)
    insert_placeholder(lid, "NEWPROMO5"); show("after insert, no reprice", lid)
    print("   reprice:", reprice(qt["Id"])); adj = show("after reprice (want 134.5)", lid)
    print("\n===== C. remove the coupon: delete its adjustment, reprice")
    for a in adj:
        if a.get("CouponCode"):
            run(["sf", "data", "delete", "record", "--sobject", "QuoteLinePriceAdjustment", "--record-id", a["Id"], "--target-org", "target"])
    print("   reprice:", reprice(qt["Id"])); show("after delete + reprice (want 269)", lid)

print("\n===== B. Ultimate (not in NewPromo): placeholder + reprice")
qt, lid = quote_with("MB-ULT")
if lid:
    print("   quote", qt["QuoteNumber"]); insert_placeholder(lid, "NEWPROMO5")
    print("   reprice:", reprice(qt["Id"])); show("after reprice (want 499, see what the placeholder becomes)", lid)
