#!/usr/bin/env bash
# CREATES test data: Mindbody usage in arrears, full run (setup, summary, invoice)
./scripts/usage/mb_usage.sh setup | grep "^QUOTE\|^ORDERS\|^journal"
./scripts/usage/mb_usage.sh summary | grep "^JOURNALS\|^RATABLE"
./scripts/usage/mb_usage.sh invoice | grep "^INVOICE\|^generate"
