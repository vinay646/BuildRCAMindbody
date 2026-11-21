#!/usr/bin/env bash
# CHANGES the org briefly: activate v7, renewal uplift check only, then back to v6
./scripts/usage/activate_version.sh 7 >/dev/null; sleep 15
./scripts/usage/renewal_uplift_check.sh
./scripts/usage/activate_version.sh 6 | tail -1
