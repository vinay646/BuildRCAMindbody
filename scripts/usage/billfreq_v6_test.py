#!/usr/bin/env python3
"""CREATES test quotes "BILLFREQ ..." in the target org. Checks that pricing procedure v6 copies the quote's Billing Frequency
(MB_Billing_Frequency__c) to the recurring lines, saves it on QuoteLineItem.BillingFrequency and applies the matching discount."""
import json, os, subprocess, time
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP

API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"
TODAY = date.today(); STAMP = time.strftime("%m%d-%H%M")
FREQ_PCT = {"Monthly": 0, "Quarterly": 2, "Semi-Annual": 4, "Annual": 8}
RESULTS = []


def run(args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def q(soql):
    try:
        return json.loads(run(["sf", "data", "query", "--query", soql, "--target-org", "target", "--json"]))["result"]["records"]
    except Exception as e:
        print("query error", e); return []


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
        "AND Id NOT IN (SELECT AccountId FROM Asset) ORDER BY CreatedDate DESC LIMIT 1")[0]["Id"]


def pbe(code):
    rows = q(f"SELECT Id, Product2Id, UnitPrice, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode = '{code}' "
             f"AND Pricebook2Id = '{PB}' AND CurrencyIsoCode = 'USD' AND IsActive = true")
    rows.sort(key=lambda r: 0 if (r.get("ProductSellingModel") or {}).get("Name") == "Term Monthly" else 1)
    return rows[0]


def lines_of(quote_id):
    return q(f"SELECT Id, Product2.ProductCode, BillingFrequency, ListPrice, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '{quote_id}'")


def check(title, rows, want):
    """want: {code: expected frequency or None}"""
    for code, f in want.items():
        r = next((x for x in rows if x["Product2"]["ProductCode"] == code), None)
        if not r:
            print(f"   FAIL {code}: no line"); RESULTS.append((title, "FAIL")); continue
        ok_f = r["BillingFrequency"] == f
        ok_p = True
        if f and code != "MB-IMP":
            exp = (Decimal(str(r["ListPrice"])) * (100 - FREQ_PCT[f]) / 100).quantize(Decimal("0.01"), ROUND_HALF_UP)
            ok_p = abs(Decimal(str(r["NetUnitPrice"])) - exp) <= Decimal("0.01")
        else:
            exp = "-"
        res = "PASS" if ok_f and ok_p else "FAIL"
        print(f"   {res} {code}: frequency {r['BillingFrequency']} (want {f}) | list {r['ListPrice']} net {r['NetUnitPrice']} (want {exp})")
        RESULTS.append((f"{title} {code}", res))


def case(title, quote_freq, lines, want, expect_block=None):
    print(f"\n===== {title}")
    opp = json.loads(run(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values",
                          f"Name='BILLFREQ {STAMP}' AccountId={ACC} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={PB} CurrencyIsoCode=USD",
                          "--target-org", "target", "--json"]))["result"]["id"]
    qrec = {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"BILLFREQ {title}"[:80], "OpportunityId": opp, "Pricebook2Id": PB,
            "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": 12, "LegalEntityId": LE}
    if quote_freq:
        qrec["MB_Billing_Frequency__c"] = quote_freq
    recs = [{"referenceId": "q1", "record": qrec}]
    for i, (code, f) in enumerate(lines):
        e = pbe(code)
        rec = {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q1.id}", "Product2Id": e["Product2Id"],
               "PricebookEntryId": e["Id"], "Quantity": 1, "StartDate": TODAY.isoformat(), "LegalEntityId": LE}
        if f:
            rec |= {"BillingFrequency": f, "EndDate": (TODAY + timedelta(days=364)).isoformat(), "PeriodBoundary": "Anniversary"}
        recs.append({"referenceId": f"l{i}", "record": rec})
    r = place({"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "all", "records": recs}})
    ok = r.get("isSuccess") is True
    if expect_block:
        msg = json.dumps(r.get("errorResponse") or r)[:300]
        res = "PASS" if not ok and expect_block.lower() in msg.lower() else "FAIL"
        print(f"   {res} expected blocked: {'saved' if ok else msg}"); RESULTS.append((title, res)); return None
    if not ok:
        print("   place failed:", json.dumps(r.get("errorResponse") or r)[:400]); RESULTS.append((title, "FAIL")); return None
    time.sleep(8)
    quote = q(f"SELECT Id, QuoteNumber, MB_Billing_Frequency__c FROM Quote WHERE OpportunityId = '{opp}' LIMIT 1")[0]
    print(f"   quote {quote['QuoteNumber']} billing frequency {quote.get('MB_Billing_Frequency__c')}")
    check(title, lines_of(quote["Id"]), want)
    return quote["Id"]


case("Quote Annual, line entered Monthly", "Annual", [("MB-ACC", "Monthly")], {"MB-ACC": "Annual"})
case("Quote blank, line keeps Quarterly", None, [("MB-ACC", "Quarterly")], {"MB-ACC": "Quarterly"})
case("Quote Semi-Annual, one-time line untouched", "Semi-Annual", [("MB-ACC", "Monthly"), ("MB-IMP", None)], {"MB-ACC": "Semi-Annual", "MB-IMP": None})
case("Quote Quarterly on Starter (CR-13 allows Monthly/Annual only)", "Quarterly", [("MB-STR", "Monthly")], {}, expect_block="billing frequency")
# rep changes the quote value on an existing quote, then the quote is repriced
qid = case("Change quote Monthly -> Annual and reprice", "Monthly", [("MB-ULT", "Monthly")], {"MB-ULT": "Monthly"})
if qid:
    r = place({"pricingPref": "Force", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "upd", "records": [{"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "PATCH", "id": qid},
                                                                                       "MB_Billing_Frequency__c": "Annual"}}]}})
    print("   reprice:", "ok" if r.get("isSuccess") else json.dumps(r.get("errorResponse") or r)[:300])
    time.sleep(8)
    check("After change + reprice", lines_of(qid), {"MB-ULT": "Annual"})

print("\n===== SUMMARY")
for t, res in RESULTS:
    print(f"  {res}  {t}")
print(f"{sum(1 for _, r in RESULTS if r == 'PASS')}/{len(RESULTS)} passed")
