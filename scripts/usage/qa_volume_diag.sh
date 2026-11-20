#!/usr/bin/env bash
# READ ONLY: why pricing fails with "Duplicate entries found while looking up VolumeDiscount"
echo "== active procedure steps mentioning Volume"
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
for n in $(sf org list metadata --metadata-type ExpressionSetDefinition --target-org target --json | jq -r '.result[].fullName' | grep -i pricing); do
  sf project retrieve start --metadata "ExpressionSetDefinition:$n" --target-org target >/dev/null 2>&1
done
for f in $(find . -name "*.expressionSetDefinition-meta.xml"); do
  python3 - "$f" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
for v in re.findall(r'<versions>.*?</versions>', s, re.S):
    st = re.search(r'<status>(\w+)</status>', v); fn = re.search(r'<fullName>([^<]+)</fullName>', v)
    if not st or st.group(1) != 'Active': continue
    rk = re.search(r'<rank>(\d+)</rank>', v); sd = re.search(r'<startDate>([^<]+)</startDate>', v)
    print('ACTIVE', fn.group(1), 'rank', rk and rk.group(1), 'start', sd and sd.group(1))
    for step in re.findall(r'<steps>(?:(?!<steps>).)*?</steps>', v, re.S):
        if 'olume' in step:
            outer = re.sub(r'<customElement>.*?</customElement>', '', step, flags=re.S)
            lab = re.search(r'<label>([^<]+)</label>', outer); at = re.search(r'<actionType>([^<]+)</actionType>', step)
            seq = re.search(r'<sequenceNumber>(\d+)</sequenceNumber>', outer)
            params = re.findall(r'<parameters>.*?<name>([^<]+)</name>.*?<value>([^<]*)</value>.*?</parameters>', step, re.S)
            print('  step', seq and seq.group(1), lab.group(1) if lab else '?', '|', at and at.group(1), '|', [(n, v[:60]) for n, v in params if 'ook' in n or 'Volume' in v or 'olume' in n or 'Table' in n or 'Field' in n][:12])
PY
done

echo "== decision tables used by pricing (all, with source object)"
sf data query --query "SELECT DeveloperName, SetupName, SourceObject, Status, UsageType FROM DecisionTable WHERE UsageType = 'DefaultPricing' OR SetupName LIKE '%Location%' OR SetupName LIKE '%Hierarchy%'" --target-org target 2>&1 | tail -30
