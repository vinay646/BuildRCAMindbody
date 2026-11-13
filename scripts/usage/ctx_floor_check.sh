#!/usr/bin/env bash
# Is MbFloorPrice in the org's RLM_SalesTransactionContext (active version), with its quote line mapping?
set -uo pipefail
rm -rf ctxf; mkdir ctxf
sf project retrieve start --api-version "$ORG_API" --metadata "ContextDefinition:RLM_SalesTransactionContext" --target-org target --target-metadata-dir ctxf --unzip --wait 10 --json > ctxf.json 2>&1 || true
F=$(find ctxf -name '*.contextDefinition*' | head -1)
python3 - "$F" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
print("versions", re.findall(r'<versionNumber>(\d+)</versionNumber>', s), "active", re.findall(r'<isActive>(\w+)</isActive>', s)[:3])
for t in ["MbFloorPrice","MbBillingMonths","MbQuoteTermMonths"]:
    m=re.search(r'<contextAttributes><contextTags><title>'+t+r'</title></contextTags>(?:(?!</contextAttributes>).)*</contextAttributes>', s, re.S)
    print(t, "attr:", re.sub(r'\s+',' ',m.group(0))[:300] if m else None)
    print(t, "mapping:", bool(re.search(r'<contextAttribute>'+t+r'</contextAttribute>', s)))
PY
