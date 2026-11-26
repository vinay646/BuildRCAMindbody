#!/usr/bin/env bash
# Read-only: the custom formula steps (and term-count steps) of the org's active RLM_DefaultPricingProcedure version, in order
T=$(mktemp -d); cd $T; sf project generate --name p >/dev/null 2>&1; cd p
sf project retrieve start --metadata "ExpressionSetDefinition:RLM_DefaultPricingProcedure" --target-org target --json >/dev/null 2>&1
f=$(find . -name 'RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml' | head -1)
python3 - "$f" <<'PY'
import sys,re
x=open(sys.argv[1]).read()
for v in re.findall(r'<versions>(.*?)</versions>', x, re.S):
    if '<status>Active</status>' not in v: continue
    print('VERSION', re.search(r'<versionNumber>(.*?)</versionNumber>', v).group(1))
    for s in re.findall(r'<steps>(.*?)</steps>', v, re.S):
        label=(re.search(r'<label>(.*?)</label>', s) or [None,''])[1] if re.search(r'<label>(.*?)</label>', s) else ''
        if re.search(r'Formula|PricingTermCount|Frequency Formula|pricing term count', s+label, re.I):
            name=re.search(r'<name>(\w+)</name>', s)
            par=re.search(r'<parentStep>(.*?)</parentStep>', s); seq=re.search(r'<sequenceNumber>(.*?)</sequenceNumber>', s)
            print('\n### STEP', label, '| name', name.group(1) if name else '', '| parent', par.group(1) if par else '-', '| seq', seq.group(1) if seq else '-', '| type', (re.search(r'<stepType>(.*?)</stepType>', s) or [None,''])[1] if re.search(r'<stepType>(.*?)</stepType>', s) else '')
            for e in re.findall(r'<expression>(.*?)</expression>', s, re.S): print('  EXPR:', e.strip()[:600])
            for r in re.findall(r'<resultParameter>(.*?)</resultParameter>', s, re.S): print('  RESULT ->', r)
            for a,b in re.findall(r'<name>(\w+)</name>\s*<output>true</output>.*?<value>(.*?)</value>', s, re.S): print('  OUT', a, '->', b)
            for a,b in re.findall(r'<sourceFieldName>(.*?)</sourceFieldName>.*?<targetFieldName>(.*?)</targetFieldName>', s, re.S): print('  MAP', a, '->', b)
            if 'customElement' in s and 'Formula' in label:
                print('  RAW', re.sub(r'\s+',' ', s)[:1500])
PY
