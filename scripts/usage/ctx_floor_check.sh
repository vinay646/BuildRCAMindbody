#!/usr/bin/env bash
# Raw org XML around MbFloorPrice vs RLM_Distributor_Unit_Price__c (an older line currency tag the procedure accepts).
set -uo pipefail
rm -rf ctxf; mkdir ctxf
sf project retrieve start --api-version "$ORG_API" --metadata "ContextDefinition:RLM_SalesTransactionContext" --target-org target --target-metadata-dir ctxf --unzip --wait 10 --json > ctxf.json 2>&1 || true
F=$(find ctxf -name '*.contextDefinition*' | head -1)
python3 - "$F" <<'PY'
import re,sys
s=re.sub(r'>\s+<','><',open(sys.argv[1]).read())
for t in ["MbFloorPrice","RLM_Distributor_Unit_Price__c"]:
    for m in re.finditer(r'<contextAttributes>(?:(?!</contextAttributes>).)*?<title>'+t+r'</title>(?:(?!</contextAttributes>).)*</contextAttributes>', s, re.S):
        print("ATTR", t, m.group(0)[:700])
    for m in re.finditer(r'<contextAttributeMappings>(?:(?!</contextAttributeMappings>).)*?<contextAttribute>'+t+r'</contextAttribute>(?:(?!</contextAttributeMappings>).)*</contextAttributeMappings>', s, re.S):
        print("MAP", t, m.group(0)[:500])
PY
