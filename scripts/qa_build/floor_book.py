#!/usr/bin/env python3
"""CHANGES the org: creates the "Mindbody Floor Prices" price book (PRC-18) with the dev org's floor prices – one entry per
plan, selling model and currency that the standard price book has – then re-saves one test quote line so the
MB Quote Line Floor Price flow fills Floor Price, and prints it. Idempotent (existing entries are kept)."""
import json, subprocess
d = json.load(open("force-app/main/default/staticresources/MB_Build_Data.json"))
FB = d["pricing"]["floorPriceBook"]


def run(a):
    r = subprocess.run(a, capture_output=True, text=True); return r.stdout or r.stderr


def q(s):
    try:
        return json.loads(run(["sf", "data", "query", "--query", s, "--target-org", "target", "--json"]))["result"]["records"]
    except Exception as e:
        print("query error", s[:80], e); return []


def create(sobj, vals):
    out = json.loads(run(["sf", "data", "create", "record", "--sobject", sobj, "--values", vals, "--target-org", "target", "--json"]))
    return (out.get("result") or {}).get("id"), out.get("message")


book = q(f"SELECT Id FROM Pricebook2 WHERE Name = '{FB['name']}'")
bid = book[0]["Id"] if book else create("Pricebook2", f"Name='{FB['name']}' IsActive=true Description='{FB['description']}'")[0]
print("floor price book", bid)
have = {(e["Product2Id"], e["ProductSellingModelId"], e["CurrencyIsoCode"]) for e in q(f"SELECT Product2Id, ProductSellingModelId, CurrencyIsoCode FROM PricebookEntry WHERE Pricebook2Id = '{bid}'")}
codes = "','".join(FB["prices"])
made = 0
for e in q(f"SELECT Product2Id, Product2.ProductCode, ProductSellingModelId, ProductSellingModel.Name, CurrencyIsoCode FROM PricebookEntry "
           f"WHERE Pricebook2.IsStandard = true AND IsActive = true AND Product2.ProductCode IN ('{codes}')"):
    price = FB["prices"][e["Product2"]["ProductCode"]].get(e["CurrencyIsoCode"])
    key = (e["Product2Id"], e["ProductSellingModelId"], e["CurrencyIsoCode"])
    if price is None or key in have:
        continue
    pid, err = create("PricebookEntry", f"Pricebook2Id={bid} Product2Id={e['Product2Id']} ProductSellingModelId={e['ProductSellingModelId']} "
                                        f"CurrencyIsoCode={e['CurrencyIsoCode']} UnitPrice={price} IsActive=true UseStandardPrice=false")
    print(f"   {e['Product2']['ProductCode']} {e['ProductSellingModel']['Name']} {e['CurrencyIsoCode']} {price}:", "ok" if pid else err)
    made += bool(pid)
print("entries created", made, "| total in book", len(q(f"SELECT Id FROM PricebookEntry WHERE Pricebook2Id = '{bid}'")))

# check: re-save the plan line of a test quote so the before-save flow runs
for qn in ("00000122", "00000123"):
    for l in q(f"SELECT Id, Product2.ProductCode FROM QuoteLineItem WHERE Quote.QuoteNumber = '{qn}' AND Product2.ProductCode IN ('{codes}')"):
        run(["sf", "data", "update", "record", "--sobject", "QuoteLineItem", "--record-id", l["Id"], "--values", "Description='floor check'", "--target-org", "target"])
        r = q(f"SELECT Product2.ProductCode, CurrencyIsoCode, NetUnitPrice, MB_Floor_Price__c, MB_Below_Floor__c FROM QuoteLineItem WHERE Id = '{l['Id']}'")[0]
        print(f"   quote {qn} {r['Product2']['ProductCode']}: floor {r['MB_Floor_Price__c']} {r['CurrencyIsoCode']}, net {r['NetUnitPrice']}, below floor {r['MB_Below_Floor__c']}")
