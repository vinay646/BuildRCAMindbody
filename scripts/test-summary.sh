#!/usr/bin/env bash
# Prints Apex test results (sf apex run test --result-format json) and adds them to the GitHub run summary.
set -uo pipefail
f="$1"
outcome=$(jq -r '.result.summary.outcome // "Failed"' "$f")
passed=$(jq -r '.result.summary.passing // 0' "$f")
failed=$(jq -r '.result.summary.failing // 0' "$f")
fails=$(jq -r '.result.tests // [] | .[] | select(.Outcome != "Pass") | "\(.ApexClass.Name).\(.MethodName): \(.Message) \(.StackTrace // "")"' "$f")
[ -z "$fails" ] && [ "$outcome" != "Passed" ] && fails=$(jq -r '.message // empty' "$f")
echo "Apex tests: $outcome – $passed passed, $failed failed"
[ -n "$fails" ] && echo "$fails"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Apex tests: $([ "$outcome" = "Passed" ] && echo "✅" || echo "❌") $outcome"
    echo
    echo "$passed passed, $failed failed."
    jq -r '.result.tests // [] | .[] | "| \(if .Outcome == "Pass" then "✅" else "❌" end) | \(.ApexClass.Name).\(.MethodName) | \((.Message // "") | gsub("\\|"; "\\|")) |"' "$f" \
      | { echo; echo '| | Test | Message |'; echo '|---|---|---|'; cat; }
    echo
  } >> "$GITHUB_STEP_SUMMARY"
fi
[ "$outcome" = "Passed" ]
