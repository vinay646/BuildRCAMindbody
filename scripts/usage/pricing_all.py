#!/usr/bin/env python3
"""All pricing scenarios built so far (MR-99..MR-106), priced through the standard Place Sales Transaction API.
CREATES test opportunities/quotes named "PRICING-ALL ..." in the target org. Prints PASS/FAIL per line with the
expected price worked out independently: list -> volume -> term -> billing frequency -> manual discount.
"""
import json
import os
import subprocess
import sys
import time
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP

API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"
STAMP = time.strftime("%m%d-%H%M")
TODAY = date.today()
RESULTS = []

VOLUME_CODES = {"MB-STR", "MB-ACC", "MB-ULT", "MB-ENT", "MB-AIC", "MB-F-AIC", "MB-APP"}
CORE = {"MB-STR", "MB-ACC", "MB-ULT", "MB-ENT"}
VOL = [(1, 3, 0), (4, 10, 5), (11, 50, 10), (51, 200, 15), (201, 10**9, 20)]
TERM = [(0, 23, 0), (24, 35, 5), (36, 10**9, 10)]
FREQ = [(1, 2, 0), (3, 5, 2), (6, 11, 4), (12, 10**9, 8)]
MONTHS = {"Monthly": 1, "Quarterly": 3, "Semi-Annual": 6, "Annual": 12}


def sh(args, body=None):
    out = subprocess.run(args, capture_output=True, text=True)
    return out.stdout


def q(soql):
    r = sh(["sf", "data", "query", "--query", soql, "--target-org", "target", "--json"])
    try:
        return json.loads(r)["result"]["records"]
    except Exception:
        print("   query error:", r[:300]); return []


def rest(method, path, body=None):
    args = ["sf", "api", "request", "rest", API + path, "--method", method, "--target-org", "target"]
    if body is not None:
        args += ["--body", json.dumps(body)]
    r = sh(args)
    try:
        return json.loads(r)
    except Exception:
        return {"raw": r[:500]}


def band(table, n):
    if n is None:
        return 0
    for lo, hi, p in table:
        if lo <= n <= hi:
            return p
    return 0


def r2(x):
    return Decimal(x).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def expected(code, lst, count, term, freq, manual):
    p = Decimal(str(lst))
    steps = []
    if code in VOLUME_CODES:
        for name, pct in (("volume", band(VOL, count)), ("term", band(TERM, term)), ("frequency", band(FREQ, MONTHS.get(freq, 1)))):
            if pct:
                p = r2(p * (100 - pct) / 100); steps.append(f"{name} {pct}%")
    if manual:
        p = r2(p * (100 - Decimal(str(manual))) / 100); steps.append(f"manual {manual}%")
    return p, steps


# ---------- reference data ----------
PB = {}
for cur in ("USD", "GBP", "AUD", "EUR"):
    rows = q(f"SELECT Pricebook2Id, Pricebook2.Name FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ULT' AND CurrencyIsoCode = '{cur}' "
             f"AND IsActive = true AND Pricebook2.IsStandard = false AND Pricebook2.IsActive = true "
             f"AND (NOT Pricebook2.Name LIKE '%Floor%') LIMIT 1")
    if rows:
        PB[cur] = rows[0]["Pricebook2Id"]
LE = {r["Name"]: r["Id"] for r in q("SELECT Id, Name FROM LegalEntity")}
LE_BY_CUR = {"USD": LE.get("Default Legal Entity - US"), "GBP": LE.get("Default Legal Entity - UK"),
             "AUD": LE.get("Default Legal Entity - AU"), "EUR": LE.get("Default Legal Entity - EU")}
PULSE = q("SELECT Id FROM Account WHERE Name = 'Pulse Fitness Brands' LIMIT 1")[0]["Id"]
ZERO = q("SELECT Id, Name FROM Account WHERE Root_Account__c = null AND (Active_Location_Count__c = null OR Active_Location_Count__c = 0) "
         "AND Id NOT IN (SELECT AccountId FROM Asset) ORDER BY CreatedDate DESC LIMIT 1")[0]
print("price books:", {c: q(f"SELECT Name FROM Pricebook2 WHERE Id = '{i}'")[0]["Name"] for c, i in PB.items()}, "| zero-location account:", ZERO["Name"])


def pbe(code, cur):
    rows = q(f"SELECT Id, Product2Id, UnitPrice, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode = '{code}' "
             f"AND Pricebook2Id = '{PB[cur]}' AND CurrencyIsoCode = '{cur}' AND IsActive = true")
    rows.sort(key=lambda r: 0 if (r.get("ProductSellingModel") or {}).get("Name") == "Term Monthly" else 1)
    return rows[0] if rows else None


def case(title, story, account, cur, term, lines, expect_block=None):
    """lines: [(code, qty, freq, manual%)]"""
    print(f"\n===== {story} | {title}")
    acc = PULSE if account == "pulse" else ZERO["Id"]
    end = (TODAY + timedelta(days=int(term * 30.44))).isoformat()
    opp = json.loads(sh(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values",
                         f"Name='PRICING-ALL {story} {STAMP}' AccountId={acc} StageName=Prospecting CloseDate={TODAY} "
                         f"Pricebook2Id={PB[cur]} CurrencyIsoCode={cur}", "--target-org", "target", "--json"]))
    opp_id = (opp.get("result") or {}).get("id")
    if not opp_id:
        print("   opportunity not created:", json.dumps(opp)[:300]); RESULTS.append((story, title, "ERROR", "opportunity")); return
    recs = [{"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"PRICING-ALL {story}",
             "OpportunityId": opp_id, "Pricebook2Id": PB[cur], "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": term,
             "LegalEntityId": LE_BY_CUR[cur]}}]
    meta = []
    for i, (code, qty, freq, manual) in enumerate(lines):
        e = pbe(code, cur)
        if not e:
            print(f"   no price book entry for {code} {cur}"); RESULTS.append((story, f"{title} {code}", "ERROR", "no entry")); continue
        rec = {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q1.id}", "Product2Id": e["Product2Id"],
               "PricebookEntryId": e["Id"], "Quantity": qty, "StartDate": TODAY.isoformat(), "EndDate": end,
               "PeriodBoundary": "Anniversary", "BillingFrequency": freq, "LegalEntityId": LE_BY_CUR[cur]}
        if "one" in ((e.get("ProductSellingModel") or {}).get("Name") or "").lower():  # one-time: no frequency or end date
            rec.pop("BillingFrequency"); rec.pop("EndDate"); rec.pop("PeriodBoundary")
        if manual:
            rec["Discount"] = manual
        recs.append({"referenceId": f"l{i}", "record": rec}); meta.append((code, qty, freq, manual))
    body = {"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
            "graph": {"graphId": "all", "records": recs}}
    r = rest("POST", "/connect/rev/sales-transaction/actions/place", body)
    ok = r.get("isSuccess") is True
    if expect_block:
        msg = json.dumps(r.get("errorResponse") or r)[:300]
        res = "PASS" if (not ok and expect_block.lower() in msg.lower()) else "FAIL"
        print(f"   {res} expected blocked ({expect_block}): {'saved' if ok else msg}")
        RESULTS.append((story, title, res, "blocked" if not ok else "not blocked")); return
    if not ok:
        print("   place failed:", json.dumps(r.get("errorResponse") or r)[:400]); RESULTS.append((story, title, "FAIL", "place failed")); return
    time.sleep(10)
    quote = q(f"SELECT Id, QuoteNumber, CalculationStatus, Hierarchy_Location_Count__c FROM Quote WHERE OpportunityId = '{opp_id}' LIMIT 1")[0]
    h = int(quote.get("Hierarchy_Location_Count__c") or 0)
    new_core = sum(qty for code, qty, _, _ in meta if code in CORE)
    count = h + new_core
    print(f"   quote {quote['QuoteNumber']} {quote['CalculationStatus']} | locations {h} + {new_core} = {count}")
    rows = q(f"SELECT Product2.ProductCode, Quantity, ListPrice, NetUnitPrice, Discount, MB_Floor_Price__c, MB_Below_Floor__c "
             f"FROM QuoteLineItem WHERE QuoteId = '{quote['Id']}'")
    for code, qty, freq, manual in meta:
        row = next((x for x in rows if x["Product2"]["ProductCode"] == code and x["Quantity"] == qty), None)
        if not row:
            print(f"   FAIL {code}: line not found"); RESULTS.append((story, f"{title} {code}", "FAIL", "no line")); continue
        exp, steps = expected(code, row["ListPrice"], count, term, freq, manual)
        net = Decimal(str(row["NetUnitPrice"])) if row["NetUnitPrice"] is not None else None
        res = "PASS" if net is not None and abs(net - exp) <= Decimal("0.01") else "FAIL"
        floor = f" | floor {row.get('MB_Floor_Price__c')} below={row.get('MB_Below_Floor__c')}" if row.get("MB_Floor_Price__c") is not None else ""
        print(f"   {res} {code} x{qty} {freq}{' manual ' + str(manual) + '%' if manual else ''}: list {row['ListPrice']} -> net {net} "
              f"(expected {exp}: {', '.join(steps) or 'no discount'}){floor}")
        RESULTS.append((story, f"{title} {code}", res, f"net {net} vs {exp}{floor}"))


ULT, ACC, STR = "MB-ULT", "MB-ACC", "MB-STR"
AIC = "MB-AIC" if q("SELECT Id FROM Product2 WHERE ProductCode = 'MB-AIC'") else "MB-F-AIC"

# MR-99 list price, currency, price book
case("Starter x3 USD monthly = $79 x 3", "MR-99", "zero", "USD", 12, [(STR, 3, "Monthly", 0)])
for cur in ("GBP", "AUD", "EUR"):
    if cur in PB:
        case(f"Ultimate x1 list price in {cur}", "MR-99", "zero", cur, 12, [(ULT, 1, "Monthly", 0)])
case("Branded App $199 and TAM $1,000", "MR-99/MR-106", "zero", "USD", 12, [("MB-APP", 1, "Monthly", 0), ("MB-TAM", 1, "Monthly", 0)])
# MR-100 volume
case("No locations + 2 new = 2 -> 0%", "MR-100", "zero", "USD", 12, [(ULT, 2, "Monthly", 0)])
case("No locations + 5 new = 5 -> 5%", "MR-100", "zero", "USD", 12, [(ULT, 5, "Monthly", 0)])
case("Pulse 12 + 2 = 14 -> 10%", "MR-100", "pulse", "USD", 12, [(ULT, 2, "Monthly", 0)])
case("Pulse 12 + 40 = 52 -> 15%", "MR-100", "pulse", "USD", 12, [(ULT, 40, "Monthly", 0)])
case("Pulse 12 + 189 = 201 -> 20%", "MR-100", "pulse", "USD", 12, [(ULT, 189, "Monthly", 0)])
case("Add-on AI Concierge gets the plan's volume band", "MR-100", "pulse", "USD", 12, [(ULT, 2, "Monthly", 0), (AIC, 2, "Monthly", 0)])
# MR-101 contract term
case("Term 24 months -> 5%", "MR-101", "pulse", "USD", 24, [(ULT, 2, "Monthly", 0)])
case("Term 36 months -> 10%", "MR-101", "pulse", "USD", 36, [(ULT, 2, "Monthly", 0)])
# MR-102 billing frequency
for f in ("Monthly", "Quarterly", "Semi-Annual", "Annual"):
    case(f"Accelerate {f}", "MR-102", "zero", "USD", 12, [(ACC, 1, f, 0)])
case("Starter Annual $79 -> $72.68", "MR-102", "zero", "USD", 12, [(STR, 1, "Annual", 0)])
case("Starter Quarterly is blocked (CR-13)", "MR-102", "zero", "USD", 12, [(STR, 1, "Quarterly", 0)], expect_block="billing frequency")
# MR-104 combined waterfall, manual discount, floor
case("Worked example: Ultimate x12, 36 mo, Annual = $371.85", "MR-104", "pulse", "USD", 36, [(ULT, 12, "Annual", 0)])
case("Worked example B: + 15% manual = $316.07, below $339 floor", "MR-104", "pulse", "USD", 36, [(ULT, 12, "Annual", 15)])
case("Accelerate 15% manual = $228.65, above floor", "MR-104", "zero", "USD", 12, [(ACC, 1, "Monthly", 15)])
# MR-106 services and hardware are never discounted
case("Services on a 12-location account: no discounts", "MR-106", "pulse", "USD", 12,
     [("MB-CON", 10, "Monthly", 0), ("MB-DCV", 2, "Monthly", 0), ("MB-IMP", 1, "Monthly", 0)])
case("Hardware: card reader, terminal, door kit", "MR-106", "pulse", "USD", 12,
     [("MB-PAY", 1, "Monthly", 0), ("MB-HW-RDR", 1, "Monthly", 0), ("MB-HW-TRM", 1, "Monthly", 0), ("MB-HW-DOOR", 1, "Monthly", 0)])

# standard quantity tiers still work (restored standard step)
tier = q("SELECT Product2.ProductCode, Product2Id, LowerBound, TierValue, TierType, CurrencyIsoCode FROM PriceAdjustmentTier "
         "WHERE PriceAdjustmentScheduleId = '84Xhm0000003oulEAA' AND LowerBound > 1 LIMIT 1")
print("\n===== standard quantity tier:", json.dumps(tier)[:300])

print("\n===== SUMMARY")
for s, t, r, d in RESULTS:
    print(f"{r:5} | {s:12} | {t} | {d}")
print(f"TOTAL {sum(1 for x in RESULTS if x[2] == 'PASS')} pass, {sum(1 for x in RESULTS if x[2] != 'PASS')} not pass")
