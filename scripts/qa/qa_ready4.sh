#!/usr/bin/env bash
# Regression probe only: Apex inserts that are ROLLED BACK (nothing saved). Prints raw errors.
set -uo pipefail
D=$(dirname "$0")
sf apex run --file "$D/apex/regression_rollback.apex" --target-org target --json > apex.json 2>&1 || true
jq -c '{status, message, name, compiled: .result.compiled, success: .result.success, line: .result.line, problem: .result.compileProblem, exception: .result.exceptionMessage}' apex.json 2>/dev/null || head -c 3000 apex.json
jq -r '.result.logs // ""' apex.json 2>/dev/null | grep -o 'RESULT.*' || true
