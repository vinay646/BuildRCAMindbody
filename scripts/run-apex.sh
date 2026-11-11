#!/usr/bin/env bash
# Runs an anonymous Apex file and prints only the result lines (debug level ERROR).
set -euo pipefail
file="$1"
out=$(sf apex run --target-org "${TARGET_ORG:-target}" --file "$file" --json)
echo "$out" | jq -r '.result.logs // ""' | grep -E 'USER_DEBUG.*\|ERROR\|' | sed -E 's/.*\|ERROR\|//' || true
if [ "$(echo "$out" | jq -r '.result.success')" != "true" ]; then
  echo "$out" | jq -r '.result.compileProblem // .result.exceptionMessage // .message'
  exit 1
fi
