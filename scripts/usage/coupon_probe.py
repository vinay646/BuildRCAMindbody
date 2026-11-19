#!/usr/bin/env python3
"""CREATES test quotes "COUPON-PROBE ...". (1) prints promotion adjustments that exist (applied in the UI);
(2) places an Accelerate line with a child QuoteLinePriceAdjustment carrying a coupon code, to see if the engine applies it."""
import json, os, subprocess, time
from datetime import date, timedelta

API = f"/services/data/v{os.environ.get('ORG_API', '68.0')}"
TODAY = date.today(); STAMP = time.strftime("%m%d-%H%M")


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


print("== promotion adjustments in the org (UI-applied)")
for a in q("SELECT QuoteLineItem.Quote.QuoteNumber, QuoteLineItem.Product2.ProductCode, QuoteLineItem.ListPrice, QuoteLineItem.NetUnitPrice, "
           "AdjustmentSource, AdjustmentType, AdjustmentValue, CouponCode, PriceAdjustmentCauseId, AppliedPromotionDate, Description, CreatedBy.Name "
           "FROM QuoteLinePriceAdjustment WHERE AdjustmentSource = 'Promotion' OR CouponCode != null ORDER BY CreatedDate DESC LIMIT 15"):
    a.pop("attributes", None); print("  ", json.dumps(a)[:500])
print("== order item promotion adjustments")
for a in q("SELECT FIELDS(STANDARD) FROM OrderItemPriceAdjustment WHERE AdjustmentSource = 'Promotion' LIMIT 5"):
    print("  ", json.dumps({k: v for k, v in a.items() if v is not None and k != "attributes"})[:400])

PB = q("SELECT Pricebook2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ULT' AND CurrencyIsoCode = 'USD' AND IsActive = true "
       "AND Pricebook2.IsStandard = false AND Pricebook2.IsActive = true AND (NOT Pricebook2.Name LIKE '%Floor%') LIMIT 1")[0]["Pricebook2Id"]
LE = q("SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - US' LIMIT 1")[0]["Id"]
ACC = q("SELECT Id FROM Account WHERE Root_Account__c = null AND (Active_Location_Count__c = null OR Active_Location_Count__c = 0) "
        "AND Id NOT IN (SELECT AccountId FROM Asset) AND (NOT Name LIKE 'QUAL-TEST%') ORDER BY CreatedDate DESC LIMIT 1")[0]["Id"]
e = q(f"SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ACC' AND Pricebook2Id = '{PB}' AND CurrencyIsoCode = 'USD' "
      f"AND IsActive = true AND ProductSellingModel.Name = 'Term Monthly'")[0]

VARIANTS = {
    "adjustment Promotion 0% + coupon": {"AdjustmentSource": "Promotion", "AdjustmentType": "AdjustmentPercentage", "AdjustmentValue": 0, "CouponCode": "NEWPROMO5"},
    "adjustment coupon only": {"CouponCode": "NEWPROMO5"},
    "adjustment Promotion cause = NewPromo": {"AdjustmentSource": "Promotion", "AdjustmentType": "AdjustmentPercentage", "AdjustmentValue": 50,
                                              "CouponCode": "NEWPROMO5", "PriceAdjustmentCauseId": "0c8hm0000000uQPAAY"},
}
for name, adj in VARIANTS.items():
    print(f"\n===== {name}")
    opp = json.loads(run(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values",
                          f"Name='COUPON-PROBE {STAMP}' AccountId={ACC} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={PB} CurrencyIsoCode=USD",
                          "--target-org", "target", "--json"]))["result"]["id"]
    recs = [{"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": f"COUPON-PROBE {name}"[:80],
                                             "OpportunityId": opp, "Pricebook2Id": PB, "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": 12, "LegalEntityId": LE}},
            {"referenceId": "l0", "record": {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q1.id}", "Product2Id": e["Product2Id"],
                                             "PricebookEntryId": e["Id"], "Quantity": 1, "StartDate": TODAY.isoformat(), "LegalEntityId": LE,
                                             "BillingFrequency": "Monthly", "EndDate": (TODAY + timedelta(days=364)).isoformat(), "PeriodBoundary": "Anniversary"}},
            {"referenceId": "a0", "record": {"attributes": {"type": "QuoteLinePriceAdjustment", "method": "POST"}, "QuoteLineItemId": "@{l0.id}"} | adj}]
    r = place({"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip",
               "graph": {"graphId": "all", "records": recs}})
    if r.get("isSuccess") is not True:
        print("   place failed:", json.dumps(r.get("errorResponse") or r)[:500]); continue
    time.sleep(8)
    quote = q(f"SELECT Id, QuoteNumber FROM Quote WHERE OpportunityId = '{opp}' LIMIT 1")[0]
    line = q(f"SELECT Id, ListPrice, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '{quote['Id']}'")[0]
    adjs = q(f"SELECT AdjustmentSource, AdjustmentType, AdjustmentValue, CouponCode, PriceAdjustmentCauseId, AppliedPromotionDate FROM QuoteLinePriceAdjustment WHERE QuoteLineItemId = '{line['Id']}'")
    print(f"   quote {quote['QuoteNumber']}: Accelerate list {line['ListPrice']} -> net {line['NetUnitPrice']} (50% = 134.5) | adjustments "
          f"{[{k: v for k, v in a.items() if k != 'attributes'} for a in adjs]}")
