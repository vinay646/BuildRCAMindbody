#!/usr/bin/env python3
"""CREATES test quotes "COUPON-FLOW ...". Quote Coupon Code -> flows MB Quote Coupon Code / MB Quote Line Coupon Code -> automatic
reprice (Apex RepriceQuotesPST on the Run Asynchronously path) -> promotion applied, with no manual reprice. Uses the rule-library promotion NewPromo (coupon NEWPROMO5: 50% off Accelerate, Term Monthly)."""
import json, os, subprocess, time
from datetime import date, timedelta

API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"
TODAY = date.today(); STAMP = time.strftime("%m%d-%H%M")
RESULTS = []


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


def entry(code):
    return q(f"SELECT Id, Product2Id, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode = '{code}' AND Pricebook2Id = '{PB}' "
             f"AND CurrencyIsoCode = 'USD' AND IsActive = true ORDER BY ProductSellingModel.Name DESC")


def line_rec(ref, code, qref="@{q1.id}"):
    es = entry(code)
    e = next((x for x in es if (x.get("ProductSellingModel") or {}).get("Name") == "Term Monthly"), es[0])
    rec = {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": qref, "Product2Id": e["Product2Id"], "PricebookEntryId": e["Id"],
           "Quantity": 1, "StartDate": TODAY.isoformat(), "LegalEntityId": LE}
    if "one" not in ((e.get("ProductSellingModel") or {}).get("Name") or "").lower():
        rec |= {"BillingFrequency": "Monthly", "EndDate": (TODAY + timedelta(days=364)).isoformat(), "PeriodBoundary": "Anniversary"}
    return {"referenceId": ref, "record": rec}


def new_quote(title, codes, coupon=None):
    opp = json.loads(run(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values",
                          f"Name='COUPON-FLOW {STAMP}' AccountId={ACC} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={PB} CurrencyIsoCode=USD",
                          "--target-org", "target", "--json"]))["result"]["id"]
    qrec = {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"COUPON-FLOW {title}"[:80], "OpportunityId": opp, "Pricebook2Id": PB,
            "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": 12, "LegalEntityId": LE}
    if coupon:
        qrec["Coupon_Code__c"] = coupon
    r = place({"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "all", "records": [{"referenceId": "q1", "record": qrec}] + [line_rec(f"l{i}", c) for i, c in enumerate(codes)]}})
    if r.get("isSuccess") is not True:
        print("   place failed:", json.dumps(r.get("errorResponse") or r)[:400]); return None
    time.sleep(6)
    return q(f"SELECT Id, QuoteNumber FROM Quote WHERE OpportunityId = '{opp}'")[0]


def set_coupon(qid, value):
    v = f"Coupon_Code__c='{value}'" if value else "Coupon_Code__c=''"
    out = json.loads(run(["sf", "data", "update", "record", "--sobject", "Quote", "--record-id", qid, "--values", v, "--target-org", "target", "--json"]))
    print(f"   set Coupon Code = {value!r}:", "ok" if out.get("status") == 0 else out.get("message"))
    time.sleep(3)


def reprice(qid):
    r = place({"pricingPref": "Force", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "upd", "records": [{"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "PATCH", "id": qid},
                                                                                       "Description": "reprice " + time.strftime("%H:%M:%S")}}]}})
    print("   reprice:", "ok" if r.get("isSuccess") else json.dumps(r.get("errorResponse") or r)[:300])
    time.sleep(6)


def check(label, qid, want, wait=90):
    """want: {code: (net, set of coupon codes expected on its adjustments)}; polls until it matches or `wait` seconds pass."""
    t0 = time.time()
    while True:
        if _check(label, qid, want, quiet=True) or time.time() - t0 > wait:
            break
        time.sleep(10)
    print(f"   (checked after {int(time.time() - t0)}s)")
    _check(label, qid, want)


def _check(label, qid, want, quiet=False):
    allok = True
    rows = q(f"SELECT Id, Product2.ProductCode, ListPrice, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '{qid}'")
    for code, (net, coupons) in want.items():
        r = next((x for x in rows if x["Product2"]["ProductCode"] == code), None)
        if not r:
            allok = False
            if not quiet:
                print(f"   FAIL {label} {code}: no line"); RESULTS.append((f"{label} {code}", "FAIL"))
            continue
        adj = q(f"SELECT AdjustmentSource, AdjustmentValue, CouponCode, PriceAdjustmentCauseId FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = '{r['Id']}'")
        got = {a["CouponCode"] for a in adj if a.get("CouponCode")}
        ok = abs(float(r["NetUnitPrice"] or 0) - net) <= 0.01 and got == coupons
        allok = allok and ok
        if quiet:
            continue
        res = "PASS" if ok else "FAIL"
        print(f"   {res} {label} {code}: net {r['NetUnitPrice']} (want {net}) | coupon adjustments "
              f"{[(a['AdjustmentValue'], a.get('CouponCode'), 'promotion' if a.get('PriceAdjustmentCauseId') else 'placeholder') for a in adj]} (want codes {sorted(coupons)})")
        RESULTS.append((f"{label} {code}", res))
    return allok


print("\n===== 1. Rep enters the coupon on an existing quote (lower case); no manual reprice")
qt = new_quote("enter later", ["MB-ACC"])
if qt:
    print("   quote", qt["QuoteNumber"])
    set_coupon(qt["Id"], "newpromo5"); check("after entering", qt["Id"], {"MB-ACC": (134.5, {"NEWPROMO5"})})
    print("\n===== 2. Rep changes the coupon to TODAY10 (Evergreen only, so no discount on a Term line)")
    set_coupon(qt["Id"], "TODAY10"); check("after change", qt["Id"], {"MB-ACC": (269.0, {"TODAY10"})})
    print("\n===== 3. Rep clears the coupon")
    set_coupon(qt["Id"], None); check("after clearing", qt["Id"], {"MB-ACC": (269.0, set())})

print("\n===== 4. Coupon on the quote when it is created, with an eligible and an ineligible line")
qt = new_quote("coupon at create", ["MB-ACC", "MB-IMP"], coupon="NEWPROMO5")
if qt:
    print("   quote", qt["QuoteNumber"])
    check("after create", qt["Id"], {"MB-ACC": (134.5, {"NEWPROMO5"}), "MB-IMP": (2500.0, {"NEWPROMO5"})})

print("\n===== 5. Rep adds an Accelerate line to a quote that already has a coupon")
qt = new_quote("add line later", ["MB-IMP"], coupon="NEWPROMO5")
if qt:
    print("   quote", qt["QuoteNumber"])
    r = place({"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "add", "records": [line_rec("l9", "MB-ACC", qref=qt["Id"])]}})
    print("   add line:", "ok" if r.get("isSuccess") else json.dumps(r.get("errorResponse") or r)[:300])
    check("after adding the line", qt["Id"], {"MB-ACC": (134.5, {"NEWPROMO5"}), "MB-IMP": (2500.0, {"NEWPROMO5"})})

print("\n===== SUMMARY")
for t, res in RESULTS:
    print(f"  {res}  {t}")
print(f"{sum(1 for _, r in RESULTS if r == 'PASS')}/{len(RESULTS)} passed")
