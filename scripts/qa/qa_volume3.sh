#!/usr/bin/env bash
# READ-ONLY: MR-100 - active pricing procedure tier steps and context mapping for location count.
set -uo pipefail
mkdir -p /tmp/md && sf project retrieve start --metadata ExpressionSetDefinition:RLM_DefaultPricingProcedure --metadata ContextDefinition:RLM_SalesTransactionContext --output-dir /tmp/md --target-org target --json > /tmp/md/r.json 2>&1
jq -c '{status, message, files: [.result.files[]? | "\(.type):\(.fullName) \(.state)"]}' /tmp/md/r.json | cut -c1-600
for f in $(find /tmp/md -name '*.expressionSetDefinition-meta.xml'); do
  python3 - "$f" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
for v in re.findall(r"<versions>.*?</versions>", s, re.S):
    name=re.search(r"<fullName>(.*?)</fullName>", v).group(1)
    st_=re.search(r"<status>(.*?)</status>", v); vn=re.search(r"<versionNumber>(.*?)</versionNumber>", v)
    print("## version", vn and vn.group(1), name, "status=", st_ and st_.group(1))
    for st in re.findall(r"<steps>.*?</steps>", v, re.S):
        if "PriceAdjustmentScheduleId" not in st: continue
        label=re.findall(r"<label>(.*?)</label>", st)[-1:]; seq=re.findall(r"<sequenceNumber>(.*?)</sequenceNumber>", st)[-1:]; parent=re.findall(r"<parentStep>(.*?)</parentStep>", st)
        params={n:val for n,val in re.findall(r"<name>([^<]*)</name><output>[^<]*</output><type>[^<]*</type><value>([^<]*)</value>", st)}
        print("   step", label, "seq", seq, "parent", parent, {k:params.get(k) for k in ("PriceAdjustmentScheduleId","LowerBound","UpperBound","Quantity","InputUnitPrice")})
    for var in re.findall(r"<variables>.*?</variables>", v, re.S):
        if re.search(r"Location|Volume|PAS|84X", var, re.I):
            print("   var", re.search(r"<name>(.*?)</name>", var).group(1), "|", (re.search(r"<value>(.*?)</value>", var) or re.search(r"<type>(.*?)</type>", var)).group(1))
    for m in re.finditer(r"Location_count__c|LocationCount|Location_Count", v): pass
    print("   mentions of location:", len(re.findall(r"[Ll]ocation", v)))
PY
done
for f in $(find /tmp/md -name '*.contextDefinition-meta.xml'); do
  python3 - "$f" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
print("## context attributes with Location:", sorted(set(re.findall(r"<title>([^<]*[Ll]ocation[^<]*)</title>", s))))
for m in re.finditer(r"<contextAttrHydrationDetails><objectName>([^<]*)</objectName><queryAttribute>([^<]*[Ll]ocation[^<]*)</queryAttribute></contextAttrHydrationDetails><contextAttribute>([^<]*)</contextAttribute>", s):
    print("   mapping", m.groups())
PY
done
