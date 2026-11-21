#!/usr/bin/env bash
# CHANGES the org: activates pricing v6, runs billing frequency, coupon and MR-103 tests; keeps v6 only if all pass, else back to v5.
set -uo pipefail
./scripts/usage/activate_version.sh 6; sleep 20
python3 scripts/usage/billfreq_v6_test.py > bf.txt 2>&1; a=$?; tail -15 bf.txt
python3 scripts/usage/coupon_v6_test.py > cp.txt 2>&1; b=$?; tail -12 cp.txt
python3 scripts/usage/mr103_test.py > mr.txt 2>&1; c=$?; sed -n '/===== SUMMARY/,$p' mr.txt
echo "results: billing frequency $a, coupon $b, mr103 $c"
if [ $((a + b + c)) -eq 0 ]; then echo "ALL PASS – version 6 stays active"; else echo "FAILURES – back to version 5"; ./scripts/usage/activate_version.sh 5; fi
