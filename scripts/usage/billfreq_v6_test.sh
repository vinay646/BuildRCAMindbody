#!/usr/bin/env bash
# CHANGES the org for the test: activates pricing v6, runs the quote billing frequency test, then re-activates v5 (KEEP=6 keeps v6).
set -uo pipefail
./scripts/usage/activate_version.sh 6; sleep 20
python3 scripts/usage/billfreq_v6_test.py; rc=$?
[ "${KEEP:-5}" = "6" ] || ./scripts/usage/activate_version.sh 5
exit $rc
