#!/usr/bin/env bash
# Runs an anonymous Apex file and prints only the result lines (debug level ERROR).
# On GitHub the lines also go to the run's summary page.
set -euo pipefail
file="$1"
title="${2:-$(basename "$file")}"
out=$(sf apex run --target-org "${TARGET_ORG:-target}" --file "$file" --json || true)
lines=$(echo "$out" | jq -r '.result.logs // ""' | grep -E 'USER_DEBUG.*\|ERROR\|' | sed -E 's/.*\|ERROR\|//' || true)
echo "$lines"
ok=$(echo "$out" | jq -r '.result.success // false')
problem=""
if [ "$ok" != "true" ]; then
  problem=$(echo "$out" | jq -r '.result.compileProblem // .result.exceptionMessage // .message // "unknown error"')
  echo "$problem"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### $title"
    echo
    if [ -n "$lines" ]; then
      echo '| Result | Item |'
      echo '|---|---|'
      echo "$lines" | while IFS= read -r l; do
        l="${l//|/\\|}"
        case "$l" in
          "===="*) echo "| **Summary** | ${l//=/} |" ;;
          READY*)   echo "| ✅ READY | ${l#READY} |" ;;
          MISSING*) echo "| ❌ MISSING | ${l#MISSING} |" ;;
          CHECK*)   echo "| ⚠️ CHECK | ${l#CHECK} |" ;;
          INFO*)    echo "| ℹ️ INFO | ${l#INFO} |" ;;
          *ERROR*)  echo "| ❌ ERROR | ${l#*ERROR} |" ;;
          *WARNING*) echo "| ⚠️ WARNING | ${l#*WARNING} |" ;;
          *)        echo "| | $l |" ;;
        esac
      done
    fi
    [ -n "$problem" ] && echo && echo "**Apex failed:** $problem"
    echo
  } >> "$GITHUB_STEP_SUMMARY"
fi
[ "$ok" = "true" ]
