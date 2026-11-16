#!/usr/bin/env python3
# CREATES test data (all names start "E2E"): end-to-end test Account -> Contact -> Opportunity -> Quote in the testing org.
import json, os, subprocess, sys, time, urllib.request, urllib.error, urllib.parse, datetime
V=os.environ.get("ORG_API","68.0")
info=json.loads(subprocess.run(["sf","org","display","--target-org","target","--json"],capture_output=True,text=True).stdout)["result"]
INST = info["instanceUrl"]
LIGHT=INST.replace(".my.salesforce.com",".lightning.force.com")
def api(method, path, body=None, extra=None):
    # Calls go through the Salesforce CLI (already logged in). An error body is a list with errorCode.
    url = path if path.startswith("/services") else f"/services/data/v{V}{path}"
    cmd=["sf","api","request","rest",url,"--method",method,"--target-org","target","--header","Sforce-Duplicate-Rule-Header: allowSave=true"]
    if body is not None: cmd+=["--body",json.dumps(body)]
    p=subprocess.run(cmd,capture_output=True,text=True)
    text=(p.stdout or "").strip()
    try: data=json.loads(text) if text else {}
    except Exception: data=text or (p.stderr or "").strip()
    bad = (isinstance(data,list) and data and isinstance(data[0],dict) and "errorCode" in data[0]) or (isinstance(data,str) and data!="") or (isinstance(data,dict) and data.get("errorCode"))
    return (400 if bad else 200), data
def q(soql):
    s,r=api("GET","/query?q="+urllib.parse.quote(soql)); return r.get("records",[]) if isinstance(r,dict) else []
def err(r):
    if isinstance(r,list): return "; ".join(x.get("message","") for x in r)
    if isinstance(r,dict):
        if r.get("errorResponse"): return "; ".join(x.get("message","") for x in r["errorResponse"])
        return r.get("message") or json.dumps(r)[:300]
    return str(r)[:300]
def create(obj, f):
    s,r=api("POST",f"/sobjects/{obj}", f); return (r.get("id"),None) if s in (200,201) else (None, err(r))
def update(obj, i, f):
    s,r=api("PATCH",f"/sobjects/{obj}/{i}", f); return None if s in (200,204) else err(r)
def delete(obj, i):
    s,r=api("DELETE",f"/sobjects/{obj}/{i}"); return None if s in (200,204) else err(r)
R=[]
def T(tid, area, name, expected, ok, actual, link=""):
    R.append({"id":tid,"area":area,"test":name,"expected":expected,"result":"Pass" if ok else "Fail","actual":actual,"link":link})
    print(f"TEST {tid} | {'PASS' if ok else 'FAIL'} | {area} | {name} | expected: {expected} | actual: {actual} {link}", flush=True)
TAG="E2E "+datetime.datetime.utcnow().strftime("%m%d-%H%M")
TODAY=datetime.date.today().isoformat()
def endd(m): d=datetime.date.today(); y=d.year+(d.month-1+m)//12; mo=(d.month-1+m)%12+1; return (datetime.date(y,mo,min(d.day,28))-datetime.timedelta(days=1)).isoformat()
# picklist values
st,desc=api("GET","/sobjects/Account/describe")
if not isinstance(desc,dict): print("DESCRIBE FAILED",st,str(desc)[:500], "instance",INST); sys.exit(1)
pv=lambda f:[p["value"] for x in desc["fields"] if x["name"]==f for p in x["picklistValues"] if p["active"]]
PAYER=(pv("Payer__c") or [None])[0]; print("Payer values",pv("Payer__c"),"Level",pv("Account_Level__c"),"Contract type",pv("Contract_Type__c"))
ADDR={"BillingStreet":"1 E2E Way","BillingCity":"Austin","BillingState":"Texas","BillingPostalCode":"73301","BillingCountry":"United States","ShippingStreet":"1 E2E Way","ShippingCity":"Austin","ShippingState":"Texas","ShippingPostalCode":"73301","ShippingCountry":"United States"}
UKADDR={"BillingStreet":"1 E2E Lane","BillingCity":"London","BillingPostalCode":"SW1A 1AA","BillingCountry":"United Kingdom","ShippingStreet":"1 E2E Lane","ShippingCity":"London","ShippingPostalCode":"SW1A 1AA","ShippingCountry":"United Kingdom"}
def acct(name, level, region, parent=None, addr=ADDR, cur="USD", extra=None):
    f={"Name":f"{TAG} {name}","Account_Level__c":level,"Vertical__c":"Fitness","Region__c":region,"CurrencyIsoCode":cur}
    if PAYER: f["Payer__c"]=PAYER
    if parent: f["ParentId"]=parent
    f.update(addr or {}); f.update(extra or {})
    return create("Account", f)
def root(i): r=q(f"SELECT Root_Account__c FROM Account WHERE Id='{i}'"); return r[0]["Root_Account__c"] if r else None
# ---------------- ACCOUNTS ----------------
corp,e=acct("Corp","Corporate","NA")
T("A01","Account","Create Corporate account (all required fields)","Account saves",bool(corp),e or "Saved", f"{LIGHT}/lightning/r/Account/{corp}/view" if corp else "")
if not corp:
    corp,e2=acct("Corp","Corporate","NA",extra={"Contract_Type__c":"Standard"})
    T("A01b","Account","Create Corporate account with Contract Type = Standard","Account saves",bool(corp),e2 or "Saved")
if not corp: print("RESULTS_JSON "+json.dumps(R)); sys.exit(0)
time.sleep(2)
cpa=q(f"SELECT AddressType, IsPrimary FROM ContactPointAddress WHERE ParentId='{corp}'")
T("A02","Account","Contact Point Addresses created from account addresses","Primary address record(s) created",len(cpa)>0,f"{len(cpa)} created: "+", ".join(f"{c['AddressType']}{' (primary)' if c['IsPrimary'] else ''}" for c in cpa))
fr,e=acct("Franchisee","Franchisee","NA",parent=corp)
T("A03","Account","Create Franchisee under Corporate","Saves; Root Account = Corporate",bool(fr) and root(fr)==corp,e or f"Root Account = {'Corporate' if root(fr)==corp else root(fr)}")
loc,e=acct("Location","Location","NA",parent=fr)
T("A04","Account","Create Location under Franchisee","Saves; Root Account = Corporate",bool(loc) and root(loc)==corp,e or f"Root Account = {'Corporate' if loc and root(loc)==corp else (root(loc) if loc else '-')}")
bad,e=create("Account",{"Name":f"{TAG} Missing fields","Account_Level__c":"Location"})
T("A05","Account","Create account without Vertical and Region","Blocked (required)",bad is None,e or "Saved")
if bad: delete("Account",bad)
if fr:
    e=update("Account",fr,{"Account_Level__c":"Location"})
    T("A06","Account","Change only Account Level of Franchisee (has a Location child) to Location","Blocked: invalid hierarchy",e is not None,e or "Saved – hierarchy check did not run")
    if e is None: update("Account",fr,{"Account_Level__c":"Franchisee"})
e=delete("Account",corp)
T("A07","Account","Delete Corporate account that has children","Blocked",e is not None,e or "Deleted")
corp2,e=acct("Corp 2","Corporate","NA")
if fr and corp2:
    e=update("Account",fr,{"ParentId":corp2}); time.sleep(2)
    T("A08","Account","Re-parent Franchisee to another Corporate","Franchisee Root Account = new Corporate",e is None and root(fr)==corp2,e or f"Franchisee Root = {'new Corporate' if root(fr)==corp2 else 'old/other'}")
    T("A09","Account","Re-parent: child Location Root Account follows","Location Root Account = new Corporate",bool(loc) and root(loc)==corp2,f"Location Root = {'new Corporate' if loc and root(loc)==corp2 else 'still old Corporate' if loc and root(loc)==corp else root(loc) if loc else '-'}")
if loc:
    e=update("Account",loc,{"BillingStreet":"2 E2E Way","ShippingStreet":"2 E2E Way"}); time.sleep(2)
    c=q(f"SELECT Street, AddressType, IsPrimary FROM ContactPointAddress WHERE ParentId='{loc}' AND IsPrimary=true")
    T("A10","Account","Change account address","Primary Contact Point Address updated to new street",e is None and any((x["Street"] or "").startswith("2 E2E") for x in c),e or ", ".join(f"{x['AddressType']}: {x['Street']}" for x in c) or "no primary address")
uk,e=acct("UK Studio","Corporate","UK",addr=UKADDR,cur="GBP")
T("A11","Account","Create UK account","Saves",bool(uk),e or "Saved")
noaddr,e=acct("No Address","Corporate","NA",addr={})
# ---------------- CONTACT ----------------
con,e=create("Contact",{"FirstName":"E2E","LastName":f"Tester {TAG[-9:]}","Email":"e2e.tester@example.org","AccountId":loc or corp})
T("B01","Contact","Create contact on Location account","Saves",bool(con),e or "Saved")
# ---------------- OPPORTUNITIES ----------------
PB={r["Name"]:r["Id"] for r in q("SELECT Id, Name FROM Pricebook2 WHERE IsActive = true")}
def opp(name, acc):
    i,e=create("Opportunity",{"Name":f"{TAG} {name}","AccountId":acc,"StageName":"Prospecting","CloseDate":TODAY})
    if not i: return None,e,{}
    time.sleep(2)
    r=q(f"SELECT Pricebook2.Name, CurrencyIsoCode, Primary_Bill_To_Address__c, Primary_Ship_To_Address__c, Location_count__c FROM Opportunity WHERE Id='{i}'")[0]
    return i,None,r
o1,e,r1=opp("NA Opp", loc or corp)
T("C01","Opportunity","Create opportunity for NA account","Saves",bool(o1),e or "Saved",f"{LIGHT}/lightning/r/Opportunity/{o1}/view" if o1 else "")
if o1:
    T("C02","Opportunity","Price book and currency from Region (NA)","North America & Asia (USD), USD",(r1.get("Pricebook2") or {}).get("Name")=="North America & Asia (USD)" and r1["CurrencyIsoCode"]=="USD",f"{(r1.get('Pricebook2') or {}).get('Name')}, {r1['CurrencyIsoCode']}")
    T("C03","Opportunity","Bill-To and Ship-To addresses copied from account","Both filled",bool(r1["Primary_Bill_To_Address__c"]) and bool(r1["Primary_Ship_To_Address__c"]),f"Bill-To {'set' if r1['Primary_Bill_To_Address__c'] else 'blank'}, Ship-To {'set' if r1['Primary_Ship_To_Address__c'] else 'blank'}")
    T("C04","Opportunity","Location Count filled","A number (0 when no active locations)",r1["Location_count__c"] is not None,f"Location Count = {r1['Location_count__c']}")
o2,e,r2=opp("UK Opp", uk) if uk else (None,"no UK account",{})
if o2: T("C05","Opportunity","Price book and currency from Region (UK)","UK (GBP), GBP",(r2.get("Pricebook2") or {}).get("Name")=="UK (GBP)" and r2["CurrencyIsoCode"]=="GBP",f"{(r2.get('Pricebook2') or {}).get('Name')}, {r2['CurrencyIsoCode']}")
o3,e,_=opp("Mismatch Opp", loc or corp)
if o3:
    e=update("Opportunity",o3,{"Pricebook2Id":PB.get("UK (GBP)")})
    T("C06","Opportunity","Change NA opportunity to UK (GBP) price book","Blocked: price book must match Region",e is not None,e or "Saved with mismatched price book")
o4,e,_=opp("No Address Opp", noaddr) if noaddr else (None,"no account",{})
# ---------------- QUOTES ----------------
def pbe(book, code):
    rows=q(f"SELECT Id, Product2Id, ProductSellingModel.Name, UnitPrice FROM PricebookEntry WHERE Pricebook2.Name='{book}' AND Product2.ProductCode='{code}' AND IsActive=true")
    rows.sort(key=lambda r: 0 if (r.get("ProductSellingModel") or {}).get("Name")=="Term Monthly" else 1)
    return rows[0] if rows else None
TERM={"MB-STR","MB-ACC","MB-ULT","MB-ENT","MB-TAM","MB-APP","MB-F-AIC"}
def quote(name, opp_id, book, lines, term=12, qextra=None):
    recs=[{"referenceId":"q1","record":dict({"attributes":{"type":"Quote","method":"POST"},"Name":f"{TAG} {name}","OpportunityId":opp_id,"Pricebook2Id":PB.get(book),"RLM_TermMonths__c":term},**(qextra or {}))}]
    for n,(code,qty,lx) in enumerate(lines):
        p=pbe(book,code)
        if not p: return None, f"No active price book entry for {code} in {book}", []
        rec={"attributes":{"type":"QuoteLineItem","method":"POST"},"QuoteId":"@{q1.id}","Product2Id":p["Product2Id"],"PricebookEntryId":p["Id"],"Quantity":qty,"StartDate":TODAY}
        if code in TERM: rec.update({"EndDate":endd(term),"PeriodBoundary":"Anniversary","BillingFrequency":"Monthly"})
        rec.update(lx or {}); recs.append({"referenceId":f"l{n}","record":rec})
    s,r=api("POST","/connect/rev/sales-transaction/actions/place",{"pricingPref":"System","catalogRatesPref":"Skip","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"e2e","records":recs}})
    e=err(r) if isinstance(r,dict) and (r.get("errorResponse") or r.get("success") is False) else (None if s<300 else err(r))
    time.sleep(2)
    qq=q(f"SELECT Id FROM Quote WHERE Name='{TAG} {name}' ORDER BY CreatedDate DESC LIMIT 1")
    qid=qq[0]["Id"] if qq else None
    ls=q(f"SELECT Id, Product2.ProductCode, UnitPrice, NetUnitPrice, CurrencyIsoCode FROM QuoteLineItem WHERE QuoteId='{qid}'") if qid else []
    return qid, e, ls
link=lambda i: f"{LIGHT}/lightning/r/Quote/{i}/view" if i else ""
NA="North America & Asia (USD)"
if o1:
    qid,e,ls=quote("Q01 Starter and Payments",o1,NA,[("MB-STR",1,None),("MB-PAY",1,None)])
    T("D01","Quote","Starter (12 months) + Mindbody Payments","Quote saves with both lines",len(ls)==2,e or f"{len(ls)} lines",link(qid))
    if qid:
        qa=q(f"SELECT ShippingStreet, BillingStreet, Pricebook2.Name, CurrencyIsoCode FROM Quote WHERE Id='{qid}'")[0]
        T("D02","Quote","Quote copies addresses from opportunity","Billing and Shipping filled",bool(qa["ShippingStreet"]) and bool(qa["BillingStreet"]),f"Billing {qa['BillingStreet']}, Shipping {qa['ShippingStreet']}",link(qid))
        st=[l for l in ls if l["Product2"]["ProductCode"]=="MB-STR"]
        T("D03","Quote","Starter price in USD","79 USD",bool(st) and float(st[0]["UnitPrice"] or 0)==79,f"{st[0]['UnitPrice']} {st[0]['CurrencyIsoCode']}" if st else "no Starter line",link(qid))
        Q1=qid
    qid,e,ls=quote("Q02 Two plans",o1,NA,[("MB-STR",1,None),("MB-ACC",1,None)])
    T("D04","Quote","Starter + Accelerate on one quote","Blocked: one plan per quote",len(ls)<2,e or f"{len(ls)} lines saved",link(qid))
    qid,e,ls=quote("Q03 Payments twice",o1,NA,[("MB-PAY",1,None),("MB-PAY",1,None)])
    T("D05","Quote","Mindbody Payments twice","Blocked: duplicate product",len(ls)<2,e or f"{len(ls)} lines saved",link(qid))
    qid,e,ls=quote("Q04 SMS overage twice",o1,NA,[("MB-SMS",1,None),("MB-SMS",1,None)])
    T("D06","Quote","SMS overage twice","Blocked: duplicate product",len(ls)<2,e or f"{len(ls)} lines saved",link(qid))
    qid,e,ls=quote("Q05 Card reader without Payments",o1,NA,[("MB-HW-RDR",1,None)])
    T("D07","Quote","Card reader without Mindbody Payments","Blocked: add Mindbody Payments",len(ls)==0,e or f"{len(ls)} lines saved",link(qid))
    qid,e,ls=quote("Q06 Card reader with Payments",o1,NA,[("MB-PAY",1,None),("MB-HW-RDR",1,None)])
    T("D08","Quote","Card reader with Mindbody Payments and address","Quote saves",len(ls)==2,e or f"{len(ls)} lines",link(qid))
    if len(ls)==2:
        pay=[l for l in ls if l["Product2"]["ProductCode"]=="MB-PAY"][0]
        e=delete("QuoteLineItem",pay["Id"])
        T("D09","Quote","Delete Mindbody Payments while card reader stays","Blocked",e is not None,e or "Payments line deleted, hardware left without Payments",link(qid))
    qid,e,ls=quote("Q07 Starter 24 months",o1,NA,[("MB-STR",1,None)],term=24)
    T("D10","Quote","Starter on a 24-month term","Quote saves (12, 24, 36 allowed)",len(ls)==1,e or f"{len(ls)} lines",link(qid))
    qid,e,ls=quote("Q08 Starter quarterly",o1,NA,[("MB-STR",1,{"BillingFrequency":"Quarterly"})])
    T("D11","Quote","Starter with Quarterly billing","Blocked: Monthly or Annual only",len(ls)==0,e or f"{len(ls)} lines saved",link(qid))
    qid,e,ls=quote("Q09 TAM 12 months",o1,NA,[("MB-TAM",1,None)],term=12)
    T("D12","Quote","TAM on a 12-month term","Quote saves",len(ls)==1,e or f"{len(ls)} lines",link(qid))
    if qid and len(ls)==1:
        e=update("Quote",qid,{"RLM_TermMonths__c":24})
        T("D13","Quote","Change TAM quote's Term to 24 months afterwards","Blocked: TAM must be 12 months",e is not None,e or "Saved with TAM on 24 months",link(qid))
    qid,e,ls=quote("Q10 TAM 24 months",o1,NA,[("MB-TAM",1,None)],term=24)
    T("D14","Quote","TAM on a 24-month term","Blocked",len(ls)==0,e or f"{len(ls)} lines saved",link(qid))
    qid,e,ls=quote("Q11 Enterprise 12 months",o1,NA,[("MB-ENT",1,None)],term=12)
    T("D15","Quote","Enterprise on a 12-month term","Blocked: 24 or 36 months",len(ls)==0,e or f"{len(ls)} lines saved",link(qid))
    qid,e,ls=quote("Q12 Enterprise without master",o1,NA,[("MB-ENT",1,None)],term=24)
    T("D16","Quote","Enterprise 24 months, no master contract","Blocked: master contract needed",len(ls)==0,e or f"{len(ls)} lines saved",link(qid))
    if corp2: update("Account",corp2,{"Contract_Type__c":"Master"})
    qid,e,ls=quote("Q13 Enterprise with master",o1,NA,[("MB-ENT",1,None)],term=24)
    T("D17","Quote","Enterprise 24 months, top account Contract Type = Master","Quote saves at $0 (price from agreement)",len(ls)==1 and float(ls[0]["UnitPrice"] or 0)==0,e or (f"saved at {ls[0]['UnitPrice']}" if ls else "no line"),link(qid))
    qid,e,ls=quote("Q14 Override without reason",o1,NA,[("MB-STR",1,None)],qextra={"Overrided_Resolved_Payer__c":corp2 or corp})
    T("D18","Quote","New quote with Payer Override and no reason","Blocked: reason required",qid is None,e or "Quote saved without a reason",link(qid))
    if 'Q1' in dir():
        e=update("Quote",Q1,{"Overrided_Resolved_Payer__c":corp2 or corp})
        T("D19","Quote","Set Payer Override on existing quote without reason","Blocked: reason required",e is not None,e or "Saved",link(Q1))
        e=update("Quote",Q1,{"Overrided_Resolved_Payer__c":corp2 or corp,"Payer_Override_Reason__c":"E2E test"})
        T("D20","Quote","Set Payer Override with a reason","Saves",e is None,e or "Saved",link(Q1))
        e2=update("Quote",Q1,{"Payer_Override_Reason__c":None})
        T("D21","Quote","Clear the reason while override stays","Blocked: reason required",e2 is not None,e2 or "Saved without a reason",link(Q1))
if o2:
    qid,e,ls=quote("Q15 UK Starter",o2,"UK (GBP)",[("MB-STR",1,None)])
    st=[l for l in ls if l["Product2"]["ProductCode"]=="MB-STR"]
    T("D22","Quote","Starter price in GBP (UK quote)","69 GBP",bool(st) and float(st[0]["UnitPrice"] or 0)==69,e or (f"{st[0]['UnitPrice']} {st[0]['CurrencyIsoCode']}" if st else "no line"),link(qid))
if o4:
    qid,e,ls=quote("Q16 Hardware no address",o4,NA,[("MB-PAY",1,None),("MB-HW-RDR",1,None)])
    T("D23","Quote","Card reader + Payments on a quote with no shipping address","Blocked: add a shipping address",len(ls)<2,e or f"{len(ls)} lines saved",link(qid))
# ---------------- CLOSE ----------------
if o3:
    e=update("Opportunity",o3,{"StageName":"Closed Won"})
    T("E01","Opportunity","Close Won an opportunity with no quote","Blocked or flagged (no quote / addresses)",e is not None,e or "Closed Won without a quote")
print("RESULTS_JSON "+json.dumps(R))
print(f"SUMMARY total={len(R)} pass={sum(1 for x in R if x['result']=='Pass')} fail={sum(1 for x in R if x['result']=='Fail')} tag={TAG}")
