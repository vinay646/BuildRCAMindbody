#!/usr/bin/env bash
# Read-only: pricing procedures in the org, active versions, and the steps/parameters related to term, frequency and volume discounts
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
echo "ACTIVE VERSIONS $(q "SELECT ExpressionSetDefinition.DeveloperName, VersionNumber, IsActive, LastModifiedDate FROM ExpressionSetVersion WHERE IsActive = true" | jq -c '[.[] | [.ExpressionSetDefinition.DeveloperName, .VersionNumber, .LastModifiedDate[0:10]]]')"
echo "DEFAULT PP: $(sf data query --query "SELECT DeveloperName, Value FROM PricingProcedureResolution LIMIT 5" --target-org target --json 2>/dev/null | jq -c '.result.records // "n/a"' | head -c 300)"
T=$(mktemp -d); cd $T; sf project generate --name p >/dev/null 2>&1; cd p
for n in $(q "SELECT ExpressionSetDefinition.DeveloperName FROM ExpressionSetVersion WHERE IsActive = true AND ExpressionSetDefinition.DeveloperName LIKE '%Pric%'" | jq -r '.[].ExpressionSetDefinition.DeveloperName' | sort -u); do
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
        if re.search(r'term|frequen|volume|schedule|tier', s, re.I):
            params=re.findall(r'<parameterName>(.*?)</parameterName>\s*<type>.*?</type>\s*<value>(.*?)</value>', s, re.S)
            params=params or re.findall(r'<name>(\w+)</name>\s*<type>\w+</type>\s*<value>(.*?)</value>', s, re.S)
            print(' -', txt.strip(), '|', '; '.join(f'{a}={b}' for a,b in params)[:600])
PY
done
