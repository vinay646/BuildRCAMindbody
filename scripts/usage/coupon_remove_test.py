#!/usr/bin/env python3
"""CREATES test data in dev: Starter + Payments quote, apply LAUNCH3, then remove the coupon; shows prices and promotion fields at each step."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
def setc(qid, code):
    r = json.loads(run(["sf", "data", "update", "record", "--sobject", "Quote", "--record-id", qid, "--values", f"Coupon_Code__c='{code}'", "--target-org", "target", "--json"]))
    return "ok" if r.get("status") == 0 else r.get("message", "")[:200]
def show(qid, tag):
    time.sleep(8)
    rows = q(f"SELECT Product2.ProductCode, ListPrice, NetUnitPrice, TotalPrice, MB_Promotion_Applied__c, MB_Price_Before_Promotion__c FROM QuoteLineItem WHERE QuoteId = '{qid}' AND Product2.ProductCode = 'MB-STR'")
    adj = q(f"SELECT AdjustmentSource, AdjustmentValue, CouponCode FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = '{qid}' AND QuoteLineItem.Product2.ProductCode = 'MB-STR' AND AdjustmentSource = 'Promotion'")
    r = rows[0]
    print(f"{tag}: Starter list {r['ListPrice']} net {r['NetUnitPrice']} total {r['TotalPrice']} | promo applied {r['MB_Promotion_Applied__c']} before-promo {r['MB_Price_Before_Promotion__c']} | promotion adjustments {[(a['AdjustmentValue'], a.get('CouponCode')) for a in adj]}")
    return r
qt = case("Coupon remove test", "CR", 12, [("MB-STR", "Term Monthly"), ("MB-PAY", "Evergreen Monthly")], None)
b = show(qt["Id"], "1 NO COUPON")
print("apply LAUNCH3:", setc(qt["Id"], "LAUNCH3")); a = show(qt["Id"], "2 WITH LAUNCH3")
print("remove coupon:", setc(qt["Id"], "")); c = show(qt["Id"], "3 COUPON REMOVED")
ok = a["NetUnitPrice"] == 39 and c["NetUnitPrice"] == b["NetUnitPrice"] and not c["MB_Promotion_Applied__c"]
print("RESULT", "PASS" if ok else "FAIL", "quote", qt["QuoteNumber"])
