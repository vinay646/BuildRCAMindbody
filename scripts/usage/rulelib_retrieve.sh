#!/usr/bin/env bash
set -uo pipefail
rm -rf rlr; mkdir rlr
sf project retrieve start --api-version "$ORG_API" --metadata RuleLibraryDefinition:RLM_RuleLibrary --metadata RuleLibraryDefinition:Configurator_Rule --metadata RuleLibraryDefinition:DRORuleLibrary --target-org target --target-metadata-dir rlr --unzip --wait 10 --json > rlr.json 2>&1 || true
jq -r '.result.messages // [] | .[] | "WARN \(.problem)"' rlr.json 2>/dev/null | head
for f in $(find rlr -type f ! -name package.xml); do echo "===== $f ($(wc -c < "$f") bytes)"; sed -e 's/^[[:space:]]*//' "$f" | tr -d '\n' | head -c 6000; echo; done
