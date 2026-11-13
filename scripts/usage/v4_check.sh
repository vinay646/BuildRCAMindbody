#!/usr/bin/env bash
set -uo pipefail
./scripts/usage/esv_check.sh
rm -rf v4r; mkdir v4r
sf project retrieve start --api-version "$ORG_API" --metadata ExpressionSetDefinition:RLM_DefaultPricingProcedure --target-org target --target-metadata-dir v4r --unzip --wait 10 --json > v4r.json 2>&1 || true
F=$(find v4r -name '*.expressionSetDefinition*' | head -1); echo "file $F"
python3 - "$F" <<'PY'
import re,sys,gzip,base64
s=open(sys.argv[1]).read()
for m in re.finditer(r'<versions>(.*?)</versions>',s,re.S):
    v=m.group(1); fn=re.search(r'<fullName>([^<]*)',v).group(1); st=re.search(r'<status>([^<]*)',v).group(1)
    print(fn, st, 'steps', v.count('<steps>'), 'promo', len(re.findall('romotion',v)), 'derived', len(re.findall('DerivedPric',v)))
    if re.search(r'<versionNumber>4</versionNumber>',v):
        open('v4.xml','w').write(v)
        print('V4_B64_START'); print(base64.b64encode(gzip.compress(v.encode())).decode()); print('V4_B64_END')
PY
