#!/usr/bin/env bash
# CHANGES the org for the test: activates pricing v6, runs the quote billing frequency and coupon code tests, then re-activates v5 (KEEP=6 keeps v6).
set -uo pipefail
./scripts/usage/activate_version.sh 6; sleep 20
a=0; [ -n "${SKIP_BF:-}" ] || { python3 scripts/usage/billfreq_v6_test.py; a=$?; }
python3 scripts/usage/coupon_v6_test.py; b=$?
[ "${KEEP:-5}" = "6" ] || ./scripts/usage/activate_version.sh 5
exit $((a + b))
