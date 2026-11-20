#!/usr/bin/env python3
"""CREATES test quotes "CML TEST ..." (on a test account "CML TEST account") and runs the product configurator on each
to check the Mindbody Plans constraint model rules: errors, messages, recommendations, products the model adds."""
import json, os, subprocess, time
from datetime import date, timedelta
API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"
TODAY = date.today(); STAMP = time.strftime("%m%d-%H%M"); RESULTS = []


def run(a):
    r = subprocess.run(a, capture_output=True, text=True); return r.stdout + (r.stderr if not r.stdout.strip() else "")


def q(soql):
    try:
        return json.loads(run(["sf", "data", "query", "--query", soql, "--target-org", "target", "--json"]))["result"]["records"]
    except Exception as e:
        print("   query error:", soql[:90], e); return []


def rest(path, body):
    out = run(["sf", "api", "request", "rest", API + path, "--method", "POST", "--body", json.dumps(body), "--target-org", "target"])
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:800]}


def create(sobj, vals):
    out = run(["sf", "data", "create", "record", "--sobject", sobj, "--values", vals, "--target-org", "target", "--json"])
    try:
        return json.loads(out)["result"]["id"]
    except Exception:
        print(f"   create {sobj} failed:", out[:400]); return None


PB = q("SELECT Pricebook2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ACC' AND CurrencyIsoCode = 'USD' AND IsActive = true "
       "AND Pricebook2.IsStandard = false AND Pricebook2.IsActive = true LIMIT 1")[0]["Pricebook2Id"]
ACC = (q("SELECT Id FROM Account WHERE Name = 'CML TEST account' LIMIT 1") or [{}])[0].get("Id") or create("Account", "Name='CML TEST account'")
print("pricebook", PB, "account", ACC)


def entry(code):
    es = q(f"SELECT Id, Product2Id, ProductSellingModel.SellingModelType, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode = '{code}' "
           f"AND Pricebook2Id = '{PB}' AND CurrencyIsoCode = 'USD' AND IsActive = true")
    if not es:
        return None
    pref = {"TermDefined": 0, "Evergreen": 1, "OneTime": 2}
    return sorted(es, key=lambda e: pref.get((e.get("ProductSellingModel") or {}).get("SellingModelType"), 3))[0]


def case(name, codes, expect, quote_vals=""):
    """expect: list of (kind, text) – kind 'error'/'message'/'recommend'/'adds'/'none'; text = substring to find"""
    print(f"\n===== {name}: {codes} {quote_vals}")
    opp = create("Opportunity", f"Name='CML TEST {STAMP}' AccountId={ACC} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={PB}")
    recs = [{"referenceId": "q", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"CML TEST {name}"[:80], "OpportunityId": opp, "Pricebook2Id": PB}}]
    for k, v in (x.split("=", 1) for x in quote_vals.split() if x):
        recs[0]["record"][k] = float(v) if v.replace(".", "").isdigit() else v
    for i, c in enumerate(codes):
        e = entry(c)
        if not e:
            print("   no price book entry for", c); RESULTS.append((name, "ERROR (no price for %s)" % c)); return
        rec = {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q.id}", "Product2Id": e["Product2Id"], "PricebookEntryId": e["Id"],
               "Quantity": 1, "StartDate": str(TODAY)}
        smt = (e.get("ProductSellingModel") or {}).get("SellingModelType")
        if smt in ("TermDefined", "Evergreen"):
            rec |= {"BillingFrequency": "Monthly", "PeriodBoundary": "Anniversary"}
        if smt == "TermDefined":
            rec["EndDate"] = str(TODAY + timedelta(days=364))
        recs.append({"referenceId": f"l{i}", "record": rec})
    r = rest("/connect/rev/sales-transaction/actions/place", {"pricingPref": "Skip", "catalogRatesPref": "Skip", "taxPref": "Skip",
             "configurationPref": {"configurationMethod": "Skip"}, "graph": {"graphId": "t", "records": recs}})
    if r.get("isSuccess") is not True:
        msg = json.dumps(r.get("errorResponse") or r)[:500]; print("   quote not created:", msg)
        # a save blocked by a QA flow/validation is reported, not judged
        RESULTS.append((name, "BLOCKED ON SAVE: " + msg[:200])); return
    time.sleep(4)
    qid = r.get("salesTransactionId") or q(f"SELECT Id FROM Quote WHERE OpportunityId = '{opp}'")[0]["Id"]
    qn = q(f"SELECT QuoteNumber FROM Quote WHERE Id = '{qid}'")[0]["QuoteNumber"]
    c = rest("/connect/cpq/configurator/actions/configure", {"transactionId": qid, "configuratorOptions": {"executePricing": False, "executeConfigurationRules": True,
             "returnProductCatalogData": False, "validateProductCatalog": False, "validateAmendRenewCancel": False, "addDefaultConfiguration": False}})
    errs = [e.get("message") if isinstance(e, dict) else str(e) for e in (c.get("errors") or [])]
    msgs = []
    for k, v in (c.get("messages") or {}).items():
        for m in (v if isinstance(v, list) else [v]):
            msgs.append(m.get("message") if isinstance(m, dict) else str(m))
    recs_ = [json.dumps(x)[:200] for x in (c.get("productRecommendations") or [])]
    items = [i.get("ProductCode") or i.get("Product") for i in ((c.get("transactionContext") or {}).get("SalesTransactionItem") or [])]
    print(f"   quote {qn} | solver {c.get('solverStatus')} success {c.get('success')}")
    print("   errors:", errs); print("   messages:", msgs); print("   recommendations:", recs_); print("   items after configure:", items)
    if "raw" in c or ("solverStatus" not in c and not errs and not msgs):
        print("   raw:", json.dumps(c)[:800])
    blob = json.dumps(errs + msgs + recs_)
    ok = True
    for kind, text in expect:
        if kind == "none":
            hit = not errs and not [m for m in msgs if m]
        elif kind == "adds":
            hit = any(text in json.dumps(i) for i in items) or text in json.dumps(c.get("transactionContext") or {})
        else:
            hit = text.lower() in blob.lower()
        print(f"   {'PASS' if hit else 'FAIL'} expect {kind}: {text}")
        ok = ok and hit
    RESULTS.append((name, "PASS" if ok else "FAIL"))


case("Baseline Accelerate alone", ["MB-ACC"], [("none", "")])
case("CR-01 two plans", ["MB-STR", "MB-ACC"], [("error", "Only one plan")])
case("CR-04 Starter + AI Concierge", ["MB-STR", "MB-F-AIC"], [("error", "Starter can't add AI Concierge")])
case("CR-04 Starter + Branded app", ["MB-STR", "MB-APP"], [("error", "Starter can't add Branded app")])
case("CR-09 hardware without Payments", ["MB-ACC", "MB-HW-RDR"], [("adds", "MB-PAY")])
case("CFG-13 Payments twice", ["MB-ACC", "MB-PAY", "MB-PAY"], [("error", "Mindbody Payments is already on this quote")])
case("CFG-13 TAM twice", ["MB-ACC", "MB-TAM", "MB-TAM"], [("error", "Technical Account Management is already on this quote")])
case("CR-07 Branded app twice", ["MB-ACC", "MB-APP", "MB-APP"], [("error", "Branded app is sold once per brand")])
case("CR-12 10+ locations", ["MB-ACC"], [("message", "Technical Account Management")], "Location_count__c=12")
case("CR-12 25+ locations", ["MB-ACC"], [("message", "Enterprise plan")], "Location_count__c=30")
case("CR-11 competitor prior system", ["MB-ACC"], [("message", "Custom data conversion")], "Prior_system__c=Vagaro")

print("\n===== SUMMARY")
for n, r in RESULTS:
    print(f"  {r}  {n}")
