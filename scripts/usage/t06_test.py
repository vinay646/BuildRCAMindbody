#!/usr/bin/env python3
"""CREATES test data "MB T06 UK ...": UK worked example T06 - Accelerate x2 locations, 12 months, billed annually in GBP.
Quote -> Closed Won -> order auto-activated -> billing schedules -> invoice (mock tax). Expect GBP 210.68/location/month, annual invoice GBP 5,056.32 + VAT."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
upd = lambda s, i, v: json.loads(run(["sf", "data", "update", "record", "--sobject", s, "--record-id", i, "--values", v, "--target-org", "target", "--json"]))
one = lambda s: (q(s) or [{}])[0]
UKPB = one("SELECT Id FROM Pricebook2 WHERE Name = 'UK (GBP)'")["Id"]
UKLE = one("SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - UK'")["Id"]
BT = one("SELECT Id FROM BillingTreatment WHERE Name = 'Mindbody - UK - Advance'")["Id"]
TT = one("SELECT Id FROM TaxTreatment WHERE Name = 'Tax - UK VAT'")["Id"]
e = one(f"SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ACC' AND Pricebook2Id = '{UKPB}' AND CurrencyIsoCode = 'GBP' AND IsActive = true")
addr = "BillingStreet='10 Downing St' BillingCity='London' BillingPostalCode='SW1A 2AA' BillingCountry='United Kingdom' ShippingStreet='10 Downing St' ShippingCity='London' ShippingPostalCode='SW1A 2AA' ShippingCountry='United Kingdom'"
ACCT = json.loads(run(["sf", "data", "create", "record", "--sobject", "Account", "--values", f"Name='MB T06 UK {STAMP}' CurrencyIsoCode=GBP {addr}", "--target-org", "target", "--json"]))["result"]["id"]
print("contact:", run(["sf", "data", "create", "record", "--sobject", "Contact", "--values", f"LastName='Billing' AccountId={ACCT} Email=billing@example.com", "--target-org", "target", "--json"])[:200])
opp = json.loads(run(["sf", "data", "create", "record", "--sobject", "Opportunity", "--values", f"Name='MB T06 UK {STAMP}' AccountId={ACCT} StageName=Prospecting CloseDate={TODAY} Pricebook2Id={UKPB} CurrencyIsoCode=GBP", "--target-org", "target", "--json"]))["result"]["id"]
end = (TODAY + timedelta(days=364)).isoformat()
recs = [{"referenceId": "q1", "record": {"attributes": {"type": "Quote", "method": "POST"}, "Name": "MB T06 UK Accelerate x2", "OpportunityId": opp, "Pricebook2Id": UKPB,
                                         "StartDate": TODAY.isoformat(), "RLM_TermMonths__c": 12, "LegalEntityId": UKLE}},
        {"referenceId": "l0", "record": {"attributes": {"type": "QuoteLineItem", "method": "POST"}, "QuoteId": "@{q1.id}", "Product2Id": e["Product2Id"], "PricebookEntryId": e["Id"],
                                         "Quantity": 2, "StartDate": TODAY.isoformat(), "EndDate": end, "LegalEntityId": UKLE, "BillingFrequency": "Annual", "PeriodBoundary": "Anniversary",
                                         "BillingTreatmentId": BT, "TaxTreatmentId": TT}}]
r = place({"pricingPref": "System", "catalogRatesPref": "Skip", "configurationPref": {"configurationMethod": "Skip"}, "taxPref": "Skip", "graph": {"graphId": "all", "records": recs}})
if r.get("isSuccess") is not True: print("place failed:", json.dumps(r)[:500]); raise SystemExit(1)
time.sleep(6)
qt = one(f"SELECT Id, QuoteNumber FROM Quote WHERE OpportunityId = '{opp}'")
ln = one(f"SELECT ListPrice, NetUnitPrice, TotalPrice, Discount, BillingFrequency FROM QuoteLineItem WHERE QuoteId = '{qt['Id']}'")
print("quote", qt["QuoteNumber"], "line:", {k: v for k, v in ln.items() if k != "attributes"})
upd("Quote", qt["Id"], "Status='Needs Review'"); time.sleep(3); upd("Quote", qt["Id"], "Status='Presented'")
upd("Opportunity", opp, "StageName='Closed Won'")
od = {}
for _ in range(30):
    time.sleep(6)
    o = one(f"SELECT MB_Order__c, MB_Order_Error__c FROM Opportunity WHERE Id = '{opp}'")
    if o.get("MB_Order_Error__c"): print("order error:", o["MB_Order_Error__c"]); raise SystemExit(1)
    if o.get("MB_Order__c"):
        od = one(f"SELECT Id, OrderNumber, Status, MB_Activation_Error__c FROM Order WHERE Id = '{o['MB_Order__c']}'")
        if od["Status"] == "Activated" or od["MB_Activation_Error__c"]: break
print("order:", {k: v for k, v in od.items() if k != "attributes"})
bs = []
for _ in range(10):
    bs = q(f"SELECT Id, Status, TotalAmount FROM BillingSchedule WHERE ReferenceEntityId = '{od.get('Id')}'")
    if bs: break
    time.sleep(6)
print("billing schedules:", [(b["Status"], b["TotalAmount"]) for b in bs])
d = TODAY.isoformat()
print("generate:", run(["sf", "api", "request", "rest", f"/services/data/v{os.environ.get('ORG_API','62.0')}/commerce/invoicing/invoices/collection/actions/generate", "--method", "POST",
                        "--body", json.dumps({"billingScheduleIds": [b["Id"] for b in bs], "action": "Draft", "invoiceDate": d, "targetDate": d}), "--target-org", "target"])[:300])
inv = {}
for _ in range(10):
    time.sleep(8)
    inv = one(f"SELECT Id, DocumentNumber, Status, CurrencyIsoCode, TotalAmount, TotalTaxAmount, TotalAmountWithTax, DueDate FROM Invoice WHERE ReferenceEntityId = '{od.get('Id')}' ORDER BY CreatedDate DESC LIMIT 1")
    if inv: break
print("invoice:", {k: v for k, v in inv.items() if k != "attributes"})
if inv: print("lines:", [(l["ChargeAmount"], l["TaxAmount"], l["StartDate"], l["EndDate"]) for l in q(f"SELECT ChargeAmount, TaxAmount, StartDate, EndDate FROM InvoiceLine WHERE InvoiceId = '{inv['Id']}'")])
ok = ln.get("NetUnitPrice") and abs(ln["NetUnitPrice"] - 210.68) < 0.01 and od.get("Status") == "Activated" and inv.get("CurrencyIsoCode") == "GBP" and abs((inv.get("TotalAmount") or 0) - 5056.32) < 0.05
print("T06", "PASS" if ok else "FAIL"); raise SystemExit(0 if ok else 1)
