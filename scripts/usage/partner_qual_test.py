#!/usr/bin/env python3
"""CR-15 / MR-79: Capital and Insurance availability by region through standard product discovery (qualification).
CREATES (or reuses) test accounts "QUAL-TEST <case>" with Region + billing country/state, then lists the Partner Products
category for each account through the Product Discovery API and checks which of Capital / Insurance / a hardware item show."""
import json, os, subprocess

API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"


def run(a):
    return subprocess.run(a, capture_output=True, text=True).stdout


def q(soql):
    try:
        return json.loads(run(["sf", "data", "query", "--query", soql, "--target-org", "target", "--json"]))["result"]["records"]
    except Exception:
        return []


def rest(method, path, body=None):
    a = ["sf", "api", "request", "rest", API + path, "--method", method, "--target-org", "target"]
    if body is not None:
        a += ["--body", json.dumps(body)]
    out = run(a)
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:300]}


CASES = [  # name, region, country, state, Capital?, Insurance?, hardware?
    ("US Texas", "NA", "United States", "TX", True, True, True),
    ("US Hawaii", "NA", "United States", "HI", True, False, True),
    ("US Alaska", "NA", "USA", "Alaska", True, False, True),
    ("Canada", "NA", "Canada", "ON", True, False, True),
    ("UK", "UK", "United Kingdom", "", True, False, True),
    ("Australia", "AU", "Australia", "NSW", True, False, True),
    ("Germany", "EU", "Germany", "", False, False, False),
]
cat = q("SELECT Id FROM ProductCatalog WHERE Name = 'Mindbody Products' LIMIT 1")[0]["Id"]
cats = {r["Name"]: r["Id"] for r in q(f"SELECT Id, Name FROM ProductCategory WHERE CatalogId = '{cat}'")}
print("categories:", list(cats))
print("qualification rows:", [(r["Product"]["ProductCode"], r["MB_Region__c"]) for r in
      q("SELECT Product.ProductCode, MB_Region__c FROM ProductQualification WHERE Product.ProductCode IN ('MB-CAP','MB-INS','MB-HW-RDR') ORDER BY Product.ProductCode")])

results = []
for name, region, country, state, want_cap, want_ins, want_hw in CASES:
    acc_name = f"QUAL-TEST {name}"
    rows = q(f"SELECT Id FROM Account WHERE Name = '{acc_name}' LIMIT 1")
    vals = f"Name='{acc_name}' MB_Region__c={region} BillingCountry='{country}' BillingState='{state}'"
    if rows:
        acc = rows[0]["Id"]
        run(["sf", "data", "update", "record", "--sobject", "Account", "--record-id", acc, "--values", vals.replace(f"Name='{acc_name}' ", ""), "--target-org", "target"])
    else:
        acc = json.loads(run(["sf", "data", "create", "record", "--sobject", "Account", "--values", vals, "--target-org", "target", "--json"])).get("result", {}).get("id")
    qr = q(f"SELECT MB_Qualification_Region__c FROM Account WHERE Id = '{acc}'")
    qreg = qr[0]["MB_Qualification_Region__c"] if qr else None
    seen = set()
    for c in ("Partner Products", "Hardware"):
        body = {"catalogId": cat, "categoryId": cats.get(c), "enableQualification": True, "userContext": {"accountId": acc},
                "pageSize": 50}
        r = rest("POST", "/connect/cpq/products", body)
        prods = (r.get("result") or r.get("products") or []) if isinstance(r, dict) else []
        if not prods and len(results) == 0:
            print(f"   {c} response:", json.dumps(r)[:800])
        for p in prods:
            seen.add(p.get("productCode") or (p.get("additionalFields") or {}).get("ProductCode") or p.get("name"))
    got = ("MB-CAP" in seen or "Mindbody Capital" in seen, "MB-INS" in seen or "Mindbody Insurance" in seen,
           "MB-HW-RDR" in seen or "Mobile card reader" in seen)
    want = (want_cap, want_ins, want_hw)
    res = "PASS" if got == want else "FAIL"
    lab = lambda t: "Capital " + ("yes" if t[0] else "no") + ", Insurance " + ("yes" if t[1] else "no") + ", card reader " + ("yes" if t[2] else "no")
    print(f"{res} {name:10} region {region} -> qualification region {qreg}: shows {lab(got)} (want {lab(want)}) | seen {sorted(x for x in seen if x)}")
    results.append(res)
print(f"\n{results.count('PASS')}/{len(results)} passed")
