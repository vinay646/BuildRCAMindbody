#!/usr/bin/env bash
# Read-only: pricing procedures in the org, active versions, and the steps/parameters related to term, frequency and volume discounts
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
echo "ACTIVE VERSIONS $(q "SELECT ExpressionSet.ApiName, VersionNumber, LastModifiedDate FROM ExpressionSetVersion WHERE IsActive = true" | jq -c '[.[] | [.ExpressionSet.ApiName, .VersionNumber, .LastModifiedDate[0:10]]]')"
echo "DEFAULT PP: $(sf data query --query "SELECT DeveloperName, Value FROM PricingProcedureResolution LIMIT 5" --target-org target --json 2>/dev/null | jq -c '.result.records // "n/a"' | head -c 300)"
T=$(mktemp -d); cd $T; sf project generate --name p >/dev/null 2>&1; cd p
for n in $(q "SELECT ExpressionSet.ApiName FROM ExpressionSetVersion WHERE IsActive = true AND ExpressionSet.ApiName LIKE '%Pric%'" | jq -r ".[].ExpressionSet.ApiName" | sort -u); do
  sf project retrieve start --metadata "ExpressionSetDefinition:$n" --target-org target --json >/dev/null 2>&1
  f=$(find . -name "$n.expressionSetDefinition-meta.xml" | head -1); [ -z "$f" ] && { echo "$n: not retrieved"; continue; }
  echo "== $n"
  python3 - "$f" <<'PY'
import sys,re
x=open(sys.argv[1]).read()
for v in re.findall(r'<versions>(.*?)</versions>', x, re.S):
    if '<status>Active</status>' not in v: continue
    for s in re.findall(r'<steps>(.*?)</steps>', v, re.S):
        name=re.search(r'<name>(.*?)</name>', s); label=re.search(r'<label>(.*?)</label>', s)
        txt=(name.group(1) if name else '')+' '+(label.group(1) if label else '')
        if re.search(r'TermBasedDiscount|Term Discount|BillingFrequencyBasedDiscounts|VolumeDiscountbyHierarchyLocations', s):
            print('RAW', re.sub(r'\s+',' ', s)[:2500]); continue
        if False:
            params=re.findall(r'<parameterName>(.*?)</parameterName>\s*<type>.*?</type>\s*<value>(.*?)</value>', s, re.S)
            params=params or re.findall(r'<name>(\w+)</name>\s*<type>\w+</type>\s*<value>(.*?)</value>', s, re.S)
            print(' -', txt.strip(), '|', '; '.join(f'{a}={b}' for a,b in params)[:600])
PY
done
