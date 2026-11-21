#!/usr/bin/env bash
# READ ONLY: the two subflows of the quote approval workflow
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
for fl in RLM_Quote_Approval_Data RLM_AA_Evaluate_Approval_Request; do sf project retrieve start --metadata "Flow:$fl" --target-org target >/dev/null 2>&1; done
for f in $(find . -name "*.flow-meta.xml"); do
python3 - "$f" <<'PY'
import sys, re
s = open(sys.argv[1]).read(); print('#####', sys.argv[1].split('/')[-1], re.search(r'<processType>([^<]+)', s).group(1))
for tag in ('recordLookups', 'decisions', 'assignments', 'formulas', 'actionCalls', 'variables', 'customErrors', 'recordUpdates'):
    for m in re.finditer(rf'<{tag}>(.*?)</{tag}>', s, re.S):
        b = m.group(1); n = re.search(r'<name>([^<]+)</name>', b)
        info = [f'{k}={v}' for k, v in re.findall(r'<(object|field|leftValueReference|stringValue|numberValue|expression|elementReference|assignToReference|isInput|isOutput|dataType)>([^<]{0,110})<', b)][:14]
        print(f'  {tag}: {n and n.group(1)} | {info}')
PY
done
