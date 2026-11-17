#!/usr/bin/env bash
# READ-ONLY: MR-100 - raw volume step of the active pricing procedure + context mapping of Locationcount__c.
set -uo pipefail
mkdir -p qa_tmp_md && sf project retrieve start --metadata ExpressionSetDefinition:RLM_DefaultPricingProcedure --metadata ContextDefinition:RLM_SalesTransactionContext --output-dir qa_tmp_md --target-org target --json > qa_tmp_md/r.json 2>&1
python3 - <<'PY'
import re,glob
s=open(glob.glob('qa_tmp_md/**/*.expressionSetDefinition-meta.xml',recursive=True)[0]).read()
v=[x for x in re.findall(r"<versions>.*?</versions>", s, re.S) if "V20" in x][0]
for st in re.findall(r"<steps>.*?</steps>", v, re.S):
    if re.search(r"[Ll]ocation|VolumePASIdConstant|Volume Discount|VolumeDiscount", st):
        st=re.sub(r"\s+"," ",st)
        print("STEP", re.findall(r"<label>(.*?)</label>", st)[-1:], re.findall(r"<stepType>(.*?)</stepType>", st), "parent", re.findall(r"<parentStep>(.*?)</parentStep>", st), "seq", re.findall(r"<sequenceNumber>(.*?)</sequenceNumber>", st)[-1:])
        for p in re.findall(r"<parameters>(.*?)</parameters>", st):
            n=re.search(r"<name>(.*?)</name>", p); val=re.search(r"<value>(.*?)</value>", p)
            if n and n.group(1) not in ("sectionCount","HideWaterfall","IsRealTime","selectedFunction","sectionJsonString1"):
                print("   ", n.group(1), "=", (val.group(1) if val else "")[:300])
for var in re.findall(r"<variables>.*?</variables>", v, re.S):
    if re.search(r"[Ll]ocation", var): print("VAR", re.sub(r"\s+"," ",var)[:400])
c=open(glob.glob('qa_tmp_md/**/*.contextDefinition-meta.xml',recursive=True)[0]).read()
for m in re.finditer(r"Locationcount__c", c):
    seg=c[max(0,m.start()-260):m.end()+120]
    if "Hydration" in seg or "queryAttribute" in seg: print("MAP ...", re.sub(r"\s+"," ",seg))
PY
