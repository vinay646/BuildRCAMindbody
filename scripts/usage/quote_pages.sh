#!/usr/bin/env bash
# READ ONLY: Quote record pages in the org and the components on each (to compare dev vs QA)
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
names=$(sf org list metadata --metadata-type FlexiPage --target-org target --json | jq -r '.result[].fullName' | grep -i quote)
echo "quote pages: $names" | tr '\n' ' '; echo
for n in $names; do sf project retrieve start --metadata "FlexiPage:$n" --target-org target >/dev/null 2>&1; done
for f in force-app/main/default/flexipages/*.xml; do
  echo "== $(basename $f)"
  python3 - "$f" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
for m in re.finditer(r'<componentName>([^<]+)</componentName>', s):
    c = m.group(1)
    if not c.startswith('flexipage:') and c not in ('force:relatedListSingleContainer', 'lst:dynamicRelatedList'):
        ctx = s[max(0, m.start()-600):m.end()+900]
        props = re.findall(r'<name>([^<]+)</name>\s*<value>([^<]{0,120})</value>', ctx)
        print('  ', c, [p for p in props][:8])
PY
done
echo "== assignment (default Quote page)"; sf data query --use-tooling-api --query "SELECT DeveloperName, EntityDefinitionId, Type FROM FlexiPage WHERE EntityDefinitionId = 'Quote'" --target-org target 2>&1 | tail -8
