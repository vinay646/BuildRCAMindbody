#!/usr/bin/env bash
# READ ONLY: configurator / revenue / quote related org settings (for dev vs QA comparison)
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
names=$(sf org list metadata --metadata-type Settings --target-org target --json | jq -r '.result[].fullName' | grep -i -E 'config|revenue|quote|industr|pricing|commerce|order|product|catalog|subscription|rca|rlm' | sort)
echo "settings: $(echo $names)"
for n in $names; do sf project retrieve start --metadata "Settings:$n" --target-org target >/dev/null 2>&1; done
for f in $(ls force-app/main/default/settings/*.xml 2>/dev/null); do
  echo "== $(basename $f .settings-meta.xml)"; python3 -c "
import re,sys; s=open('$f').read()
for k,v in re.findall(r'<(\w+)>([^<]{1,80})</\1>', s): print('  ',k,'=',v)"
done
