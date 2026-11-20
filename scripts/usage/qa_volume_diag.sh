#!/usr/bin/env bash
# READ ONLY: why pricing fails with "Duplicate entries found while looking up VolumeDiscount"
echo "== pricing procedure versions"
sf data query --use-tooling-api --query "SELECT DeveloperName, VersionNumber, Status, ExpressionSetDefinition.DeveloperName FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName LIKE '%Pricing%' ORDER BY ExpressionSetDefinition.DeveloperName, VersionNumber" --target-org target 2>&1 | tail -20
echo "== decision tables like Volume"
sf data query --query "SELECT Id, DeveloperName, MasterLabel, SourceObject, Status, Type, UsageType, SetupName FROM DecisionTable WHERE DeveloperName LIKE '%olume%' OR MasterLabel LIKE '%olume%'" --target-org target --json 2>&1 | jq -c '.result.records[]? | del(.attributes)' 
echo "== parameters"
for id in $(sf data query --query "SELECT Id FROM DecisionTable WHERE DeveloperName LIKE '%olume%' OR MasterLabel LIKE '%olume%'" --target-org target --json | jq -r '.result.records[].Id'); do
  sf data query --query "SELECT DecisionTable.DeveloperName, FieldName, Usage, Operator, Sequence, DataType FROM DecisionTableParameter WHERE DecisionTableId = '$id' ORDER BY Sequence" --target-org target --json | jq -c '.result.records[] | {t: .DecisionTable.DeveloperName, FieldName, Usage, Operator, Sequence}'
done
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
    print('ACTIVE', fn.group(1))
    for step in re.findall(r'<steps>(?:(?!<steps>).)*?</steps>', v, re.S):
        if 'olume' in step:
            lab = re.search(r'<label>([^<]+)</label>', step); lk = re.findall(r'<name>(LookUp\w*|DecisionTable\w*|ListPriceField|.*Volume.*)</name><output>\w+</output><type>\w+</type><value>([^<]*)</value>', step)
            print('  step', lab.group(1) if lab else '?', lk[:8])
PY
done
