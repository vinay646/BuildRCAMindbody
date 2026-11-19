#!/usr/bin/env python3
"""CREATES test quotes "COUPON ..." in the target org. Checks that pricing procedure v6 applies the promotion that owns the
quote's Coupon Code (Quote.Coupon_Code__c) to the eligible lines, and nothing when the code is blank or unknown."""
import json, os, subprocess, time
from datetime import date, timedelta

API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"
TODAY = date.today(); STAMP = time.strftime("%m%d-%H%M")
RESULTS = []


def run(a):
    return subprocess.run(a, capture_output=True, text=True).stdout


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
        "AND Id NOT IN (SELECT AccountId FROM Asset) AND (NOT Name LIKE 'QUAL-TEST%') ORDER BY CreatedDate DESC LIMIT 1")[0]["Id"]
print("coupons:", [(c["CouponCode"], c["Status"], c["Promotion"]["Name"], c["Promotion"]["IsActive"], c["Promotion"]["IsAutomatic"])
                   for c in q("SELECT CouponCode, Status, Promotion.Name, Promotion.IsActive, Promotion.IsAutomatic FROM Coupon")])


def pbe(code):
    rows = q(f"SELECT Id, Product2Id, UnitPrice, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode = '{code}' "
             f"AND Pricebook2Id = '{PB}' AND CurrencyIsoCode = 'USD' AND IsActive = true")
    rows.sort(key=lambda r: 0 if (r.get("ProductSellingModel") or {}).get("Name") == "Term Monthly" else 1)
    return rows[0]


def case(title, coupon, lines, want):
    """lines: [code]; want: {code: expected net unit price}"""
    print(f"\n===== {title} (coupon {coupon!r})")
    opp = json.loads(run(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values",
                          f"Name='COUPON {STAMP}' AccountId={ACC} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={PB} CurrencyIsoCode=USD",
                          "--target-org", "target", "--json"]))["result"]["id"]
    qrec = {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"COUPON {title}"[:80], "OpportunityId": opp, "Pricebook2Id": PB,
            "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": 12, "LegalEntityId": LE}
    if coupon:
        qrec["Coupon_Code__c"] = coupon
    recs = [{"referenceId": "q1", "record": qrec}]
    for i, code in enumerate(lines):
        e = pbe(code)
        rec = {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q1.id}", "Product2Id": e["Product2Id"],
               "PricebookEntryId": e["Id"], "Quantity": 1, "StartDate": TODAY.isoformat(), "LegalEntityId": LE}
        if "one" not in ((e.get("ProductSellingModel") or {}).get("Name") or "").lower():
            rec |= {"BillingFrequency": "Monthly", "EndDate": (TODAY + timedelta(days=364)).isoformat(), "PeriodBoundary": "Anniversary"}
        recs.append({"referenceId": f"l{i}", "record": rec})
    r = place({"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "all", "records": recs}})
    if r.get("isSuccess") is not True:
        print("   place failed:", json.dumps(r.get("errorResponse") or r)[:400]); RESULTS.append((title, "FAIL")); return None
    time.sleep(8)
    quote = q(f"SELECT Id, QuoteNumber, Coupon_Code__c FROM Quote WHERE OpportunityId = '{opp}' LIMIT 1")[0]
    print(f"   quote {quote['QuoteNumber']} coupon {quote.get('Coupon_Code__c')}")
    rows = q(f"SELECT Id, Product2.ProductCode, ListPrice, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '{quote['Id']}'")
    for code, exp in want.items():
        row = next((x for x in rows if x["Product2"]["ProductCode"] == code), None)
        if not row:
            print(f"   FAIL {code}: no line"); RESULTS.append((f"{title} {code}", "FAIL")); continue
        adj = q(f"SELECT AdjustmentSource, AdjustmentType, AdjustmentValue, CouponCode, PromotionId FROM QuoteLinePriceAdjustment "
                f"WHERE QuoteLineItemId = '{row['Id']}' AND (PromotionId != null OR CouponCode != null)")
        res = "PASS" if abs(float(row["NetUnitPrice"] or 0) - exp) <= 0.01 else "FAIL"
        print(f"   {res} {code}: list {row['ListPrice']} -> net {row['NetUnitPrice']} (want {exp}) | promotion adjustments "
              f"{[(a.get('AdjustmentSource'), a.get('AdjustmentType'), a.get('AdjustmentValue'), a.get('CouponCode')) for a in adj]}")
        RESULTS.append((f"{title} {code}", res))
    return quote["Id"]


case("SWITCH50 on Accelerate = 50% off", "SWITCH50", ["MB-ACC"], {"MB-ACC": 134.50})
case("LAUNCH3 on Starter = $39 fixed", "LAUNCH3", ["MB-STR"], {"MB-STR": 39.00})
case("GROW2 on Starter = 100% off", "GROW2", ["MB-STR"], {"MB-STR": 0.00})
case("SWITCH50 leaves services alone", "SWITCH50", ["MB-ACC", "MB-IMP"], {"MB-ACC": 134.50, "MB-IMP": 2500.00})
case("SWITCH50 does not target Starter", "SWITCH50", ["MB-STR"], {"MB-STR": 79.00})
case("No coupon = list price", None, ["MB-ACC"], {"MB-ACC": 269.00})
case("Unknown coupon BOGUS = list price", "BOGUS", ["MB-ACC"], {"MB-ACC": 269.00})
case("Lower case switch50 (information)", "switch50", ["MB-ACC"], {"MB-ACC": 134.50})
qid = case("Add coupon later and reprice", None, ["MB-ULT"], {"MB-ULT": 499.00})
if qid:
    r = place({"pricingPref": "Force", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "upd", "records": [{"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "PATCH", "id": qid},
                                                                                       "Coupon_Code__c": "SWITCH50"}}]}})
    print("   reprice:", "ok" if r.get("isSuccess") else json.dumps(r.get("errorResponse") or r)[:300])
    time.sleep(8)
    row = q(f"SELECT NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '{qid}'")[0]
    res = "PASS" if abs(float(row["NetUnitPrice"] or 0) - 249.50) <= 0.01 else "FAIL"
    print(f"   {res} MB-ULT after adding SWITCH50 and repricing: net {row['NetUnitPrice']} (want 249.50)")
    RESULTS.append(("Add coupon later and reprice", res))

print("\n===== SUMMARY")
for t, res in RESULTS:
    print(f"  {res}  {t}")
print(f"{sum(1 for _, r in RESULTS if r == 'PASS')}/{len(RESULTS)} passed")
