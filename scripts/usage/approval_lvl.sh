#!/usr/bin/env bash
# READ ONLY: RLM_Approval_Level__c definition + approval step assignees
sf sobject describe --sobject Quote --target-org target --json | jq -c '.result.fields[] | select(.name=="RLM_Approval_Level__c" or .name=="RLM_Payment_Terms__c") | {name, type, calculated, calculatedFormula}'
sf sobject describe --sobject QuoteLineItem --target-org target --json | jq -c '[.result.fields[] | select(.name|test("Approv";"i")) | {name, type, calculatedFormula}]'
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
sf project retrieve start --metadata "Flow:RLM_Quote_Smart_Approval" --target-org target >/dev/null 2>&1
f=$(find . -name "RLM_Quote_Smart_Approval.flow-meta.xml")
python3 - "$f" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
for m in re.finditer(r'<stageSteps>(.*?)</stageSteps>', s, re.S):
    b = m.group(1)
    if 'ApprovalStep' not in b: continue
    n = re.search(r'<name>([^<]+)</name>', b).group(1)
    a = re.search(r'<assignees>(.*?)</assignees>', b, re.S)
    print('STEP', n, '| assignees:', re.sub(r'\s+', ' ', a.group(1))[:400] if a else None)
for n in ('fmlExitStage1', 'fmlManagerApproval', 'rejectedQuote'):
    m = re.search(rf'<formulas>\s*<name>{n}</name>.*?<expression>([^<]+)</expression>', s, re.S); print('FORMULA', n, m and m.group(1)[:300])
PY
