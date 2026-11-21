#!/usr/bin/env bash
# READ ONLY: quote approval flow structure + queues/groups usable as approvers
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
sf project retrieve start --metadata "Flow:RLM_Quote_Smart_Approval" --target-org target >/dev/null 2>&1
f=$(find . -name "RLM_Quote_Smart_Approval.flow-meta.xml"); echo "flow file $(wc -c < "$f") bytes"
python3 - "$f" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
for t in ('processType', 'status', 'apiVersion'): print(t, re.search(f'<{t}>([^<]+)</{t}>', s).group(1))
st = re.search(r'<start>.*?</start>', s, re.S).group(0); print('START', re.sub(r'\s+', ' ', st)[:600])
for tag in ('orchestratedStages', 'stageSteps', 'decisions', 'recordLookups', 'actionCalls', 'formulas'):
    for m in re.finditer(rf'<{tag}>(.*?)</{tag}>', s, re.S):
        b = m.group(1); n = re.search(r'<name>([^<]+)</name>', b); l = re.search(r'<label>([^<]+)</label>', b)
        extra = ' '.join(re.findall(r'<(actionName|actionType|stepSubtype|leftValueReference|operator|stringValue|numberValue|expression)>([^<]{0,90})<', b)[:0])
        info = [f'{k}={v}' for k, v in re.findall(r'<(actionName|stepSubtype|leftValueReference|stringValue|numberValue|expression|elementReference)>([^<]{0,80})<', b)][:10]
        print(f'  {tag}: {n and n.group(1)} | {l and l.group(1)} | {info}')
PY
echo "== queues for Quote / groups"
sf data query --query "SELECT Queue.Name, Queue.DeveloperName FROM QueueSobject WHERE SobjectType = 'Quote'" --target-org target --json | jq -c '[.result.records[] | .Queue.DeveloperName]'
sf data query --query "SELECT DeveloperName, Type FROM Group WHERE Type IN ('Regular','Queue') AND (DeveloperName LIKE '%Sales%' OR DeveloperName LIKE '%Finance%' OR DeveloperName LIKE '%Desk%' OR DeveloperName LIKE '%Approv%')" --target-org target --json | jq -c '[.result.records[] | "\(.DeveloperName):\(.Type)"]'
sf data query --query "SELECT Name, UserRole.Name, IsActive FROM User WHERE IsActive = true AND UserType = 'Standard'" --target-org target --json | jq -c '[.result.records[] | "\(.Name)/\(.UserRole.Name)"]'
