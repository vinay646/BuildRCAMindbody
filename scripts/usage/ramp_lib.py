"""Standard Revenue Cloud ramp schedule on an existing quote, through the Place / Clone Sales Transaction APIs
import os
(the same calls the Ramp Schedule UI makes): group -> EditGroup -> CloneSalesTransaction -> EditRampSchedule.
Expects run(), q() and API from the caller's globals (mr103_test.py helpers)."""
import json, time
from datetime import date, timedelta


def _rest(path, body):
    out = run(["sf", "api", "request", "rest", API + path, "--method", "POST", "--body", json.dumps(body), "--target-org", "target"])
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:600]}


def _place(action, quote_id, records):
    recs = [{"referenceId": quote_id, "record": {"attributes": {"type": "Quote", "method": "PATCH", "id": quote_id}}}] + records
    return _rest("/connect/rev/sales-transaction/actions/place",
                 {"groupRampAction": action, "pricingPref": "System", "graph": {"graphId": f"{action}_{quote_id}", "records": recs}})


def _grp(gid, fields):
    return {"referenceId": gid, "record": {"attributes": {"type": "QuoteLineGroup", "method": "PATCH", "id": gid}, **fields}}


def add_months(d, m):
    y, mo = divmod(d.month - 1 + m, 12)
    import calendar
    return date(d.year + y, mo + 1, min(d.day, calendar.monthrange(d.year + y, mo + 1)[1]))


def ramp(quote_id, start, months, term, line_codes, log=print):
    """Two segments: months 1..months (promotion) and months+1..term (list price)."""
    e1 = add_months(start, months) - timedelta(days=1); s2 = e1 + timedelta(days=1); e2 = add_months(start, term) - timedelta(days=1)
    mk = lambda vals: json.loads(run(["sf", "data", "create", "record", "--sobject", "QuoteLineGroup", "--values", vals, "--target-org", "target", "--json"]))
    p = mk(f"QuoteId={quote_id} Name='Promotion ramp' Type=RampScheduleGroup StartDate={start} EndDate={e2}")
    pid = (p.get("result") or {}).get("id"); log("   ramp parent group:", pid or json.dumps(p)[:300])
    g = mk(f"QuoteId={quote_id} Name='Months 1-{months}' ParentQuoteLineGroupId={pid} StartDate={start} EndDate={e1}")
    g0 = (g.get("result") or {}).get("id"); log("   segment 1 group:", g0 or json.dumps(g)[:300])
    if not (pid and g0):
        return None
    lines = [l for l in q(f"SELECT Id, Product2.ProductCode FROM QuoteLineItem WHERE QuoteId = '{quote_id}'") if l["Product2"]["ProductCode"] in line_codes]
    for l in lines:
        log("   move line", l["Product2"]["ProductCode"], run(["sf", "data", "update", "record", "--sobject", "QuoteLineItem", "--record-id", l["Id"],
                                                             "--values", f"QuoteLineGroupId={g0}", "--target-org", "target"]).strip()[-160:])
    r = _place("EditGroup", quote_id, [_grp(g0, {"IsRamped": True, "SegmentType": "Custom", "StartDate": str(start), "EndDate": str(e1)})])
    log("   EditGroup:", json.dumps(r)[:400])
    time.sleep(4)
    log("   after EditGroup:", q(f"SELECT Product2.ProductCode, RampIdentifier, SegmentIdentifier, SegmentType, IsPrimarySegment FROM QuoteLineItem WHERE QuoteLineGroupId = '{g0}'"))
    for opts in ({"lineScope": os.environ.get("LINE_SCOPE", "AllLines")},):
        body = {"recordIds": [g0], "salesTransactionId": quote_id}
        if opts:
            body["options"] = opts
        r = _rest("/connect/rev/sales-transaction/actions/clone", body)
        log("   Clone", opts, json.dumps(r)[:300])
        for _ in range(18):
            time.sleep(5)
            segs = q(f"SELECT Id FROM QuoteLineGroup WHERE ParentQuoteLineGroupId = '{pid}' ORDER BY CreatedDate")
            if len(segs) >= 2 and q(f"SELECT Id FROM QuoteLineItem WHERE QuoteLineGroupId = '{segs[-1]['Id']}'"):
                break
        log("   lines after clone:", [(l["Product2"]["ProductCode"], l["QuoteLineGroupId"], l["StartDate"], l["EndDate"]) for l in q(f"SELECT Product2.ProductCode, QuoteLineGroupId, StartDate, EndDate FROM QuoteLineItem WHERE QuoteId = '{quote_id}'")])
        segs = q(f"SELECT Id, Name FROM QuoteLineGroup WHERE ParentQuoteLineGroupId = '{pid}' ORDER BY CreatedDate")
        if len(segs) >= 2 and q(f"SELECT Id FROM QuoteLineItem WHERE QuoteLineGroupId = '{segs[-1]['Id']}'"):
            break
        for extra in []:
            log("   remove empty segment", run(["sf", "data", "delete", "record", "--sobject", "QuoteLineGroup", "--record-id", extra["Id"], "--target-org", "target"]).strip()[-120:])
    segs = q(f"SELECT Id, Name FROM QuoteLineGroup WHERE ParentQuoteLineGroupId = '{pid}' ORDER BY CreatedDate")
    if len(segs) < 2:
        log("   no second segment:", segs); return None
    g1 = segs[-1]["Id"]
    r = _place("EditRampSchedule", quote_id, [_grp(g0, {"Name": f"Months 1-{months}", "StartDate": str(start), "EndDate": str(e1)}),
                                              _grp(g1, {"Name": f"Months {months + 1}-{term}", "StartDate": str(s2), "EndDate": str(e2)})])
    log("   EditRampSchedule:", json.dumps(r)[:400])
    time.sleep(4)
    return g0, g1


def show(quote_id, log=print):
    for g in q(f"SELECT Id, Name, Type, IsRamped, SegmentType, StartDate, EndDate FROM QuoteLineGroup WHERE QuoteId = '{quote_id}' ORDER BY StartDate, CreatedDate"):
        log("   group", g["Name"], g["Id"], g["Type"], g["IsRamped"], g["SegmentType"], g["StartDate"], g["EndDate"])
    for l in q(f"SELECT Id, Product2.ProductCode, QuoteLineGroupId, StartDate, EndDate, SegmentIdentifier, IsPrimarySegment, ListPrice, NetUnitPrice, TotalPrice "
               f"FROM QuoteLineItem WHERE QuoteId = '{quote_id}' ORDER BY StartDate"):
        log("   line", l["Product2"]["ProductCode"], l["QuoteLineGroupId"], l["StartDate"], l["EndDate"], l["SegmentIdentifier"], l["IsPrimarySegment"],
            l["ListPrice"], l["NetUnitPrice"], l["TotalPrice"])
