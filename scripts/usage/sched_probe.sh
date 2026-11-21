#!/usr/bin/env bash
# Probe (validation only, may create a scheduler if the body is valid): invoice scheduler Connect API
API="/services/data/v$ORG_API"
for p in /commerce/invoicing/invoice-schedulers /commerce/billing/invoice-schedulers; do
  echo "== $p"; sf api request rest "$API$p" --method POST --body '{}' --target-org target 2>&1 | head -c 600; echo
done
