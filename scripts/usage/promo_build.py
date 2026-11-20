#!/usr/bin/env python3
"""CHANGES the org: replaces the script-loaded LAUNCH3 / SWITCH50 / GROW2 (no rule library, never applied) with standard
rule-library promotions created through the Global Promotions Management API, same coupon codes (MR-103 / spec PRC-07)."""
import json, os, subprocess, sys
from datetime import datetime, timezone

API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"


def run(a):
    r = subprocess.run(a, capture_output=True, text=True)
    return r.stdout + r.stderr


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
        return {"raw": out[:600]}


def pid(code):
    return q(f"SELECT Id FROM Product2 WHERE ProductCode = '{code}' LIMIT 1")[0]["Id"]


PSM = {r["Name"]: r["Id"] for r in q("SELECT Id, Name FROM ProductSellingModel WHERE Name IN ('Term Monthly','Evergreen Monthly')")}
LIB_ID = q("SELECT RuleLibraryId FROM Promotion WHERE Name = 'NewPromo' AND RuleLibraryId != null LIMIT 1")[0]["RuleLibraryId"]
# start well before today: the engine compares with the quote date in the org time zone (Pacific)
START = "2026-11-01T08:00:00.000Z"
P = {c: pid(c) for c in ("MB-STR", "MB-ACC", "MB-ULT", "MB-ENT")}
NAMES = {"MB-STR": "Starter", "MB-ACC": "Accelerate", "MB-ULT": "Ultimate", "MB-ENT": "Enterprise"}
print("rule library", LIB_ID, "| selling models", PSM)

# 1. remove the old script-loaded promotions (no rule library) and their coupons
for name in ("LAUNCH3", "SWITCH50", "GROW2"):
    for p in q(f"SELECT Id FROM Promotion WHERE Name = '{name}'" + " AND RuleLibraryId = null AND CreatedDate < 2026-11-20T00:00:00Z"):
        for c in q(f"SELECT Id FROM Coupon WHERE PromotionId = '{p['Id']}'"):
            print(f"   delete coupon {c['Id']}:", run(["sf", "data", "delete", "record", "--sobject", "Coupon", "--record-id", c["Id"], "--target-org", "target"]).strip()[:120])
        for t in q(f"SELECT Id FROM PromotionTarget WHERE PromotionId = '{p['Id']}'"):
            run(["sf", "data", "delete", "record", "--sobject", "PromotionTarget", "--record-id", t["Id"], "--target-org", "target"])
        print(f"   delete promotion {name} {p['Id']}:", run(["sf", "data", "delete", "record", "--sobject", "Promotion", "--record-id", p["Id"], "--target-org", "target"]).strip()[:160])


def reward(codes, models, dtype, value):
    return {"scope": "BundledProduct",
            "scopeDetails": [{"productCode": c, "name": NAMES[c], "id": P[c]} for c in codes],
            "doNotDefineRewards": False,
            "rewardDetailsList": [{"productSellingModel": {"name": m, "id": PSM[m]}, "discountType": dtype, "discountValue": value} for m in models],
            "childItems": [], "type": "PSMDiscount", "isPrimaryReward": False}


def cat_reward(scope, value):
    return {"scope": scope, "scopeDetails": [{"id": "0ZGhm0000003Fk5GAE", "name": "Subscriptions"}], "doNotDefineRewards": False,
            "rewardDetailsList": [{"productSellingModel": {"name": "Term Monthly", "id": PSM["Term Monthly"]}, "discountType": "PercentageOff", "discountValue": value}],
            "childItems": [], "type": "PSMDiscount", "isPrimaryReward": False}


def body(name, coupon, codes, rewards, description):
    # one rule per product: the rule template allows one product in a reward scope
    return {"promotionDetails": {"name": name, "description": description, "currencyIsoCode": "USD", "isAutomatic": False, "startDateTime": START,
                                 "ruleLibrary": {"id": LIB_ID},
                                 "promotionEligibility": {"eligibleCoupons": [{"couponCode": coupon, "startDateTime": START, "status": "Active"}],
                                                          "eligibleProducts": [{"id": P[c], "productCode": c, "name": NAMES[c], "productType": "BundledProduct"} for c in codes]}},
            "rules": [{"ruleName": f"{name}Reward", "priority": 1, "journalType": "Customer Purchase",
                       "templateName": "GetRewardsBasedOnSellingModel", "eventConfiguration": [], "rewardConfiguration": rewards}]}


def create(name, coupon, codes, reward_options, description):
    if os.environ.get("ONLY") and name not in os.environ["ONLY"].split(","):
        return None
    if os.environ.get("REBUILD"):
        # in use on quotes, so update in place: deactivate, PUT the full definition, activate
        for ex in q(f"SELECT Id FROM Promotion WHERE Name = '{name}'"):
            print(f"   deactivate {name}:", run(["sf", "data", "update", "record", "--sobject", "Promotion", "--record-id", ex["Id"], "--values", "IsActive=false", "--target-org", "target"]).strip()[-80:])
            r = rest("PUT", f"/global-promotions-management/promotions/{ex['Id']}", body(name, coupon, codes, reward_options[0], description))
            print(f"   PUT {name}:", json.dumps(r)[:400])
            print(f"   activate {name}:", run(["sf", "data", "update", "record", "--sobject", "Promotion", "--record-id", ex["Id"], "--values", "IsActive=true", "--target-org", "target"]).strip()[-200:])
            return r
    if q(f"SELECT Id FROM Promotion WHERE Name = '{name}' AND RuleLibraryId != null"):
        print(f"   {name} already built, skipped"); return None
    for rewards in reward_options:
        r = rest("POST", "/global-promotions-management/promotions", body(name, coupon, codes, rewards, description))
        ok = isinstance(r, dict) and (r.get("promotionId") or r.get("id") or (r.get("promotionDetails") or {}).get("id") or r.get("isSuccess"))
        print(f"   create {name} ({rewards[0]['rewardDetailsList'][0]['discountType']} {rewards[0]['rewardDetailsList'][0]['discountValue']}):", json.dumps(r)[:700])
        if ok:
            new_id = (r.get("promotionDetails") or {}).get("id") or r.get("promotionId") or r.get("id")
            print(f"   activate {name}:", run(["sf", "data", "update", "record", "--sobject", "Promotion", "--record-id", new_id, "--values", "IsActive=true", "--target-org", "target"]).strip()[:300])
            return r
    return None


create("SWITCH50", "SWITCH50", ["MB-ACC", "MB-ULT"], [[reward([c], ["Term Monthly"], "PercentageOff", 50) for c in ("MB-ACC", "MB-ULT")]],
       "Competitor switch: 50% off Accelerate or Ultimate for the first 6 months (spec PRC-07, CR-10).")
create("GROW2", "GROW2", ["MB-STR", "MB-ACC", "MB-ULT"], [[cat_reward(sc, 100)] for sc in ("Category", "ProductCategory", "category")],
       "Existing customer adding a location: 2 months free on the new location (spec PRC-07, CR-10).")
create("LAUNCH3", "LAUNCH3", ["MB-STR"],
       [[reward(["MB-STR"], ["Term Monthly"], t, v)] for t, v in (("PriceOverride", 40),)],
       "New logo: Starter at $39 per location for the first 3 months (spec PRC-07, PRC-08, CR-10).")

print("\n== result")
for p in q("SELECT Id, Name, IsActive, IsAutomatic, RuleLibraryId, StartDateTime FROM Promotion ORDER BY CreatedDate"):
    print("  ", p["Name"], p["Id"], "active" if p["IsActive"] else "inactive", "rule library" if p.get("RuleLibraryId") else "NO rule library",
          [c["CouponCode"] for c in q(f"SELECT CouponCode FROM Coupon WHERE PromotionId = '{p['Id']}'")])
for name in ("LAUNCH3", "SWITCH50", "GROW2"):
    for p in q(f"SELECT Id FROM Promotion WHERE Name = '{name}'"):
        g = rest("GET", f"/global-promotions-management/promotions/{p['Id']}")
        print(f"   {name} rules:", json.dumps([{"r": x.get("ruleName"), "rw": [[(d["discountType"], d["discountValue"], d["productSellingModel"]["name"]) for d in y["rewardDetailsList"]] for y in x.get("rewardConfiguration", [])]} for x in g.get("rules", [])])[:600])
