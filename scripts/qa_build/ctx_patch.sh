#!/usr/bin/env bash
# CHANGES the org when DRY != 1: retrieve RLM_SalesTransactionContext, add the two Mindbody Plans attributes, deploy.
set -uo pipefail
R=$PWD; W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
sf project retrieve start --metadata "ContextDefinition:RLM_SalesTransactionContext" --target-org target >/dev/null 2>&1
f=$(find . -name "RLM_SalesTransactionContext*.xml" | head -1); echo "retrieved $f ($(wc -c < "$f") bytes)"
cp "$f" before.xml; python3 "$R/scripts/qa_build/ctx_patch.py" "$f" || exit 1
echo "size before $(wc -c < before.xml), after $(wc -c < "$f")"
if [ "${DRY:-1}" = "1" ]; then flag="--dry-run"; echo "CHECK ONLY"; else flag=""; fi
sf project deploy start $flag --source-dir force-app/main/default/contextDefinitions --target-org target --wait 30 --json > r.json || true
jq -c '{status: .result.status, success: .result.success, errors: [.result.details.componentFailures? | if type=="array" then .[] else . end | select(.!=null) | .problem]}' r.json 2>/dev/null || head -c 1500 r.json
