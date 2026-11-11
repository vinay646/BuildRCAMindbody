#!/usr/bin/env bash
# Prints a deploy/validate result (sf --json output) and adds it to the GitHub run summary. Fails on errors.
set -uo pipefail
f="$1"; title="$2"
status=$(jq -r '.result.status // .name // "Failed"' "$f")
ok=$(jq -r '.result.success // false' "$f")
comps=$(jq -r '.result.numberComponentsDeployed // 0' "$f")
errs=$(jq -r '[.result.details.componentFailures // [] | if type=="array" then .[] else . end
              | "\(.componentType) \(.fullName): \(.problem)"] | .[]' "$f" 2>/dev/null)
[ -z "$errs" ] && [ "$ok" != "true" ] && errs=$(jq -r '.message // empty' "$f")
echo "$title: $status ($comps components)"
[ -n "$errs" ] && echo "$errs"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### $title: $([ "$ok" = "true" ] && echo "✅" || echo "❌") $status"
    echo
    echo "$comps components."
    if [ -n "$errs" ]; then
      echo; echo '| Problem |'; echo '|---|'
      echo "$errs" | while IFS= read -r l; do echo "| ${l//|/\\|} |"; done
    fi
    echo
  } >> "$GITHUB_STEP_SUMMARY"
fi
[ "$ok" = "true" ]
