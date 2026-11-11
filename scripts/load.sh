#!/usr/bin/env bash
# Runs one MindbodyBuildLoader step; fails the run if the step reported errors.
set -euo pipefail
step="$1"
tmp=$(mktemp)
echo "MindbodyBuildLoader.run('$step');" > "$tmp.apex"
./scripts/run-apex.sh "$tmp.apex" "Loader step: $step" | tee "$tmp.log"
if grep -qE "\"$step\": [1-9][0-9]* error" "$tmp.log"; then
  echo "::error::Loader step $step reported errors – see the lines starting with ERROR above"
  exit 1
fi
