#!/usr/bin/env python3
"""CREATES a test quote "MR103 ramp probe" (Starter + Payments, 12 months), ramps it 3 + 9 months with the org's
RLM_RampScheduleService (API path, async), then prints the groups and lines."""
import json, os, subprocess, time, tempfile
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
qt = case("ramp probe", "probe", 12, [("MB-STR", "Term Monthly"), ("MB-PAY", "Evergreen Monthly")], None)
s1 = TODAY; e1 = TODAY + timedelta(days=int(3 * 30.44)) - timedelta(days=1)
s2 = e1 + timedelta(days=1); e2 = TODAY + timedelta(days=int(12 * 30.44)) - timedelta(days=1)
apex = f"""
RLM_RampScheduleRequest r = new RLM_RampScheduleRequest();
r.quoteId = '{qt['Id']}'; r.action = 'CREATE'; r.useDmlApproach = false;
r.scheduleHeader = new RLM_RampScheduleRequest.ScheduleHeader();
r.scheduleHeader.scheduleName = 'Promotion ramp'; r.scheduleHeader.scheduleType = 'CUSTOM';
RLM_RampScheduleRequest.SegmentDefinition a = new RLM_RampScheduleRequest.SegmentDefinition();
a.sequence = 1; a.name = 'Months 1-3'; a.segmentType = 'CUSTOM'; a.startDate = Date.valueOf('{s1}'); a.endDate = Date.valueOf('{e1}');
RLM_RampScheduleRequest.SegmentDefinition b = new RLM_RampScheduleRequest.SegmentDefinition();
b.sequence = 2; b.name = 'Months 4-12'; b.segmentType = 'CUSTOM'; b.startDate = Date.valueOf('{s2}'); b.endDate = Date.valueOf('{e2}');
r.segments = new List<RLM_RampScheduleRequest.SegmentDefinition>{{a, b}};
RLM_RampScheduleResponse res = new RLM_RampScheduleService().execute(r);
System.debug('RAMP ' + JSON.serialize(res));
"""
f = tempfile.NamedTemporaryFile("w", suffix=".apex", delete=False); f.write(apex); f.close()
out = run(["sf", "apex", "run", "--file", f.name, "--target-org", "target"])
print("   ramp:", [l[l.find("RAMP"):][:600] for l in out.splitlines() if "RAMP" in l and "USER_DEBUG" in l] or out[-800:])
for i in range(12):
    time.sleep(10)
    jobs = q("SELECT Status, ExtendedStatus FROM AsyncApexJob WHERE ApexClass.Name = 'RLM_RampMigrationQueueable' ORDER BY CreatedDate DESC LIMIT 1")
    print("   job:", jobs)
    if jobs and jobs[0]["Status"] in ("Completed", "Failed", "Aborted"):
        break
for g in q(f"SELECT Id, Name, Type, IsRamped, SegmentType, StartDate, EndDate, ParentQuoteLineGroupId FROM QuoteLineGroup WHERE QuoteId = '{qt['Id']}' ORDER BY StartDate"):
    print("   group", {k: v for k, v in g.items() if k != "attributes"})
for l in q(f"SELECT Id, Product2.ProductCode, QuoteLineGroupId, StartDate, EndDate, RampIdentifier, SegmentIdentifier, SegmentType, IsPrimarySegment, NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '{qt['Id']}' ORDER BY StartDate"):
    print("   line", l["Product2"]["ProductCode"], {k: v for k, v in l.items() if k not in ("attributes", "Product2")})
