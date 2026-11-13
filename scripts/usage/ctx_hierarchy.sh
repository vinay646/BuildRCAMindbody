#!/usr/bin/env bash
# Does the standard sales transaction context have the category-hierarchy node the promotions engine needs, and does ours?
set -uo pipefail
rm -rf ctxh; mkdir ctxh
sf project retrieve start --api-version "$ORG_API" --metadata "ContextDefinition:SalesTransactionContext__stdctx" --metadata "ContextDefinition:RLM_SalesTransactionContext" --target-org target --target-metadata-dir ctxh --unzip --wait 10 --json > ctxh.json 2>&1 || true
jq -r '.result.messages // [] | .[] | "WARN \(.problem)"' ctxh.json 2>/dev/null | head
for f in $(find ctxh -type f -name '*.contextDefinition*'); do
  echo "===== $f ($(wc -c < "$f") bytes)"
  python3 - "$f" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
print("versions:", re.findall(r'<versionNumber>(\d+)</versionNumber>', s)[:5], "active:", re.findall(r'<isActive>(\w+)</isActive>', s)[:5])
nodes=re.findall(r'<contextNodes>(.*?)</contextNodes>', s, re.S)
names=[]
for n in nodes:
    st=re.sub(r'<contextAttributes>.*?</contextAttributes>','',n,flags=re.S)
    names.append(re.findall(r'<title>([^<]*)</title>', st)[-1:] )
print("node count", len(nodes))
print("category/hierarchy nodes:", [x for x in names if x and re.search('ategor|ierarch', x[0])])
for n in nodes:
    if re.search(r'ProductCategoryHierarchy', n):
        print("NODE XML:", re.sub(r'\s+',' ',n)[:3000])
for m in re.findall(r'<contextMappings>(.*?)</contextMappings>', s, re.S):
    if 'Hierarch' in m:
        t=re.search(r'<title>([^<]*)</title>', re.sub(r'<contextNodeMappings>.*?</contextNodeMappings>','',m,flags=re.S))
        for nm in re.findall(r'<contextNodeMappings>(?:(?!</contextNodeMappings>).)*Hierarch(?:(?!</contextNodeMappings>).)*</contextNodeMappings>', m, re.S):
            print("MAPPING", t.group(1) if t else '?', re.sub(r'\s+',' ',nm)[:1500])
PY
done
