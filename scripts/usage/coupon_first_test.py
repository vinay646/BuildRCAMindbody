#!/usr/bin/env python3
"""CREATES test data in dev: coupon entered before any product. LAUNCH3 on an empty quote -> add Starter (waits) -> add Payments (applies)."""
import json, os, subprocess, time
from datetime import timedelta
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
opp = json.loads(run(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values", f"Name='MR103 coupon first {STAMP}' AccountId={ACC} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={PB} CurrencyIsoCode=USD", "--target-org", "target", "--json"]))["result"]["id"]
qid = json.loads(run(["sf", "data", "create", "record", "--sobject", "Quote", "--values", f"Name='MR103 coupon first' OpportunityId={opp} Pricebook2Id={PB} StartDate={TODAY} RLM_TermMonths__c=12 LegalEntityId={LE}", "--target-org", "target", "--json"]))["result"]["id"]
r = json.loads(run(["sf", "data", "update", "record", "--sobject", "Quote", "--record-id", qid, "--values", "Coupon_Code__c='LAUNCH3'", "--target-org", "target", "--json"]))
print("1 LAUNCH3 on empty quote:", "accepted" if r.get("status") == 0 else "REJECTED " + r.get("message", "")[:200])
def add(code, model):
    e = entry(code, model)
    rec = {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": qid, "Product2Id": e["Product2Id"], "PricebookEntryId": e["Id"], "Quantity": 1,
           "StartDate": TODAY.isoformat(), "LegalEntityId": LE, "BillingFrequency": "Monthly", "PeriodBoundary": "Anniversary"}
    if model == "Term Monthly": rec["EndDate"] = (TODAY + timedelta(days=364)).isoformat()
    out = place({"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
                 "graph": {"graphId": "g", "records": [{"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "PATCH", "id": qid}}}, {"referenceId": "l1", "record": rec}]}})
    return "ok" if out.get("isSuccess") else json.dumps(out.get("errorResponse"))[:300]
def starter(tag):
    time.sleep(10)
    rows = q(f"SELECT NetUnitPrice, MB_Promotion_Applied__c FROM QuoteLineItem WHERE QuoteId = '{qid}' AND Product2.ProductCode = 'MB-STR'")
    adj = q(f"SELECT AdjustmentValue, CouponCode, PriceAdjustmentCauseId FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = '{qid}' AND AdjustmentSource = 'Promotion'")
    print(f"{tag}: Starter net {rows[0]['NetUnitPrice'] if rows else '-'} promo {rows[0]['MB_Promotion_Applied__c'] if rows else '-'} | adjustments {[(a['AdjustmentValue'], a.get('CouponCode'), bool(a.get('PriceAdjustmentCauseId'))) for a in adj]}")
    return rows[0] if rows else {}
print("2 add Starter:", add("MB-STR", "Term Monthly")); s1 = starter("2 STARTER ONLY")
print("3 add Payments:", add("MB-PAY", "Evergreen Monthly")); s2 = starter("3 STARTER + PAYMENTS")
ok = r.get("status") == 0 and s1.get("NetUnitPrice") == 79 and s2.get("NetUnitPrice") == 39
print("RESULT", "PASS" if ok else "FAIL", "quote", q(f"SELECT QuoteNumber FROM Quote WHERE Id = '{qid}'")[0]["QuoteNumber"])
