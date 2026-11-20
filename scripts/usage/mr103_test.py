#!/usr/bin/env python3
"""CREATES test quotes "MR103 ...". MR-103 acceptance criteria through the Quote Coupon Code: each case sets up the quote
(term, prior system, payments, data conversion), enters the coupon and reads the line prices and promotion adjustments."""
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
# existing customer: an account with assets
EXISTING = q("SELECT AccountId FROM Asset WHERE AccountId != null ORDER BY CreatedDate DESC LIMIT 1")[0]["AccountId"]


def entry(code, model="Term Monthly"):
    es = q(f"SELECT Id, Product2Id, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode = '{code}' AND Pricebook2Id = '{PB}' "
           f"AND CurrencyIsoCode = 'USD' AND IsActive = true")
    return next((x for x in es if (x.get("ProductSellingModel") or {}).get("Name") == model), es[0])


def case(title, story, term, lines, coupon, prior=None, want=None, account=None):
    """lines: [(code, selling model or None for one-time)]; want: {code: expected net or None = list (no promotion)}"""
    print(f"\n===== {story} | {title} (term {term}, prior system {prior}, coupon {coupon})")
    opp_vals = f"Name='MR103 {STAMP}' AccountId={account or ACC} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={PB} CurrencyIsoCode=USD"
    if prior:
        opp_vals += f" MB_Prior_System__c='{prior}'"
    opp = json.loads(run(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values", opp_vals, "--target-org", "target", "--json"]))
    oid = (opp.get("result") or {}).get("id")
    if not oid:
        print("   opportunity not created:", json.dumps(opp)[:300]); RESULTS.append((story, title, "ERROR")); return
    recs = [{"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"MR103 {title}"[:80], "OpportunityId": oid,
                                             "Pricebook2Id": PB, "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": term, "LegalEntityId": LE}}]
    for i, (code, model) in enumerate(lines):
        e = entry(code, model or "One-Time")
        rec = {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q1.id}", "Product2Id": e["Product2Id"], "PricebookEntryId": e["Id"],
               "Quantity": 1, "StartDate": TODAY.isoformat(), "LegalEntityId": LE}
        if model:
            rec |= {"BillingFrequency": "Monthly", "PeriodBoundary": "Anniversary"}
            if model != "Evergreen Monthly":
                rec["EndDate"] = (TODAY + timedelta(days=int(term * 30.44))).isoformat()
        recs.append({"referenceId": f"l{i}", "record": rec})
    r = place({"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "all", "records": recs}})
    if r.get("isSuccess") is not True:
        print("   place failed:", json.dumps(r.get("errorResponse") or r)[:400]); RESULTS.append((story, title, "ERROR (quote not created)")); return
    time.sleep(5)
    qt = q(f"SELECT Id, QuoteNumber FROM Quote WHERE OpportunityId = '{oid}'")[0]
    if not coupon:
        print(f"   quote {qt['QuoteNumber']} {qt['Id']} created (no coupon)"); return qt
    out = json.loads(run(["sf", "data", "update", "record", "--sobject", "Quote", "--record-id", qt["Id"], "--values", f"Coupon_Code__c='{coupon}'",
                          "--target-org", "target", "--json"]))
    print(f"   quote {qt['QuoteNumber']}: coupon set:", "ok" if out.get("status") == 0 else "REJECTED - " + out.get("message", "")[:300])
    if out.get("status") != 0:
        expected_reject = all(v is None for v in (want or {}).values())
        RESULTS.append((story, title, "PASS (coupon rejected)" if expected_reject else "FAIL (coupon rejected)")); return
    time.sleep(6)
    rows = q(f"SELECT Id, Product2.ProductCode, ListPrice, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '{qt['Id']}'")
    ok = True
    for code, exp in (want or {}).items():
        row = next((x for x in rows if x["Product2"]["ProductCode"] == code), None)
        adj = q(f"SELECT AdjustmentValue, CouponCode, PriceAdjustmentCauseId FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = '{row['Id']}'") if row else []
        promo = [(a["AdjustmentValue"], a.get("CouponCode")) for a in adj if a.get("PriceAdjustmentCauseId")]
        net = row["NetUnitPrice"] if row else None
        target = row["ListPrice"] if (row and exp is None) else exp
        good = row is not None and abs(float(net or 0) - float(target)) <= 0.01 and (bool(promo) == (exp is not None))
        ok = ok and good
        print(f"   {'PASS' if good else 'FAIL'} {code}: list {row and row['ListPrice']} -> net {net} (want {target}{'' if exp is not None else ', no promotion'}) | promotion adjustments {promo}")
    RESULTS.append((story, title, "PASS" if ok else "FAIL"))


# MR-103 AC2: LAUNCH3 $39 per location (months 1-3), Starter, 12-month term, Payments on the quote
case("LAUNCH3 Starter 12 months with Payments", "AC2", 12, [("MB-STR", "Term Monthly"), ("MB-PAY", "Evergreen Monthly")], "LAUNCH3", want={"MB-STR": 39.0})
# AC3: SWITCH50 50% off Accelerate, 24 months, competitor prior system, data conversion on the quote
case("SWITCH50 Accelerate 24 months, competitor, data conversion", "AC3", 24, [("MB-ACC", "Term Monthly"), ("MB-DCV", None)], "SWITCH50",
     prior="Vagaro", want={"MB-ACC": 127.78})
# AC4: GROW2 2 months free per added location (new location on an existing customer)
case("GROW2 Accelerate added location, existing customer", "AC4", 12, [("MB-ACC", "Term Monthly")], "GROW2", want={"MB-ACC": 0.0}, account=EXISTING)
case("GROW2 on a new customer", "AC4b", 12, [("MB-ACC", "Term Monthly")], "GROW2", want={"MB-ACC": None})
# AC5: LAUNCH3 on a 6-month term, or without Payments: rejected
# (a 6-month term is already blocked by CR-13 for Starter, so the rejection is shown with "no Payments")
case("LAUNCH3 Starter 12 months, no Payments", "AC5", 12, [("MB-STR", "Term Monthly")], "LAUNCH3", want={"MB-STR": None})
case("LAUNCH3 for an existing customer", "AC5b", 12, [("MB-STR", "Term Monthly"), ("MB-PAY", "Evergreen Monthly")], "LAUNCH3", want={"MB-STR": None}, account=EXISTING)
# AC6: SWITCH50 when prior system is None: rejected
case("SWITCH50 Accelerate 24 months, prior system None", "AC6", 24, [("MB-ACC", "Term Monthly"), ("MB-DCV", None)], "SWITCH50",
     prior="None", want={"MB-ACC": None})
# control: a rule-library promotion (NewPromo, 50% Accelerate) through the same path
case("Control: NEWPROMO5 Accelerate", "control", 12, [("MB-ACC", "Term Monthly")], "NEWPROMO5", want={"MB-ACC": 134.5})

print("\n===== SUMMARY")
for s, t, r in RESULTS:
    print(f"  {r}  {s}  {t}")
