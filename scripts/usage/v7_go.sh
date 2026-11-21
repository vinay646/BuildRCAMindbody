#!/usr/bin/env bash
# CHANGES the org: activates pricing v7, runs billing frequency, MR-103 and renewal uplift tests; keeps v7 only if all pass, else back to v6.
set -uo pipefail
./scripts/usage/activate_version.sh 7; sleep 20
python3 scripts/usage/billfreq_v6_test.py > bf.txt 2>&1; a=$?; grep "passed\|FAIL" bf.txt | tail -5
python3 scripts/usage/mr103_test.py > mr.txt 2>&1; b=$?; sed -n '/===== SUMMARY/,$p' mr.txt
./scripts/usage/renewal_uplift_check.sh; c=$?
echo "results: billing frequency $a, mr103 $b, renewal uplift $c"
if [ $((a + b + c)) -eq 0 ]; then echo "ALL PASS – version 7 stays active"; else echo "FAILURES – back to version 6"; ./scripts/usage/activate_version.sh 6; fi
