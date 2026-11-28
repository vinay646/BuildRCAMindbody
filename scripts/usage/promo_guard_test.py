#!/usr/bin/env python3
"""CHANGES test data in dev: on quote 00000398 (coupon LAUNCH3, Starter $39) and 00000397 (no coupon) adds a 50% promotion adjustment to the Starter line, as if switched on in the configurator; checks that the guard removes it after commit."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
def state(qn):
    qid = q(f"SELECT Id FROM Quote WHERE QuoteNumber = '{qn}'")[0]["Id"]
    l = q(f"SELECT Id, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '{qid}' AND Product2.ProductCode = 'MB-STR'")[0]
    adj = q(f"SELECT AdjustmentValue, CouponCode, Description FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = '{l['Id']}' AND AdjustmentSource = 'Promotion'")
    return qid, l, [(a["AdjustmentValue"], a.get("CouponCode"), (a.get("Description") or "")[:20]) for a in adj]
for qn in ("00000398", "00000397"):
    qid, l, adj = state(qn); print(f"{qn} BEFORE: Starter net {l['NetUnitPrice']} promotions {adj}")
    r = json.loads(run(["sf", "data", "create", "record", "--sobject", "QuoteLinePriceAdjustment", "--values",
        f"QuoteLineItemId={l['Id']} AdjustmentSource=Promotion AdjustmentType=AdjustmentPercentage AdjustmentValue=50 Description='Configurator toggle test'", "--target-org", "target", "--json"]))
    print(f"{qn} added 50% promotion:", "ok" if r.get("status") == 0 else r.get("message", "")[:200])
time.sleep(90)
res = []
for qn, want_net in (("00000398", 39), ("00000397", 79)):
    qid, l, adj = state(qn); bad = [a for a in adj if a[0] == 50]
    print(f"{qn} AFTER: Starter net {l['NetUnitPrice']} promotions {adj}"); res.append(not bad and l["NetUnitPrice"] == want_net)
print("RESULT", "PASS" if all(res) else "FAIL")
