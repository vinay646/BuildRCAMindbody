#!/usr/bin/env bash
# READ ONLY: tags/data types of the QA context attributes the model reads
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
sf project retrieve start --metadata "ContextDefinition:RLM_SalesTransactionContext" --target-org target >/dev/null 2>&1
f=$(find . -name "RLM_SalesTransactionContext*.xml" | head -1)
python3 - "$f" <<'PY'
import sys, xml.etree.ElementTree as ET
NS='{http://soap.sforce.com/2006/04/metadata}'
r=ET.parse(sys.argv[1]).getroot()
for v in r.findall(NS+'contextDefinitions') + r.findall(NS+'contextDefinitionVersions'):
    if v.findtext(NS+'isActive')!='true': continue
    for n in v.iter(NS+'contextNodes'):
        if n.findtext(NS+'title')!='SalesTransaction': continue
        for a in n.findall(NS+'contextAttributes'):
            t=a.findtext(NS+'title')
            if t and ('ocation' in t or 'rior' in t):
                print(t, '| type', a.findtext(NS+'dataType'), '| tags', [x.findtext(NS+'title') for x in a.findall(NS+'contextTags')], '| fieldType', a.findtext(NS+'fieldType'))
PY
