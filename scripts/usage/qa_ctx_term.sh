#!/usr/bin/env bash
# Read-only: how the org's RLM_SalesTransactionContext maps quote-line term/date fields into pricing
R=$(pwd); T=$(mktemp -d); cd $T; sf project generate --name p >/dev/null 2>&1; cd p
sf project retrieve start --metadata "ContextDefinition:RLM_SalesTransactionContext" --target-org target --json >/dev/null 2>&1
python3 "$R/scripts/usage/py/ctx_term.py" "$(find . -name 'RLM_SalesTransactionContext.contextDefinition-meta.xml' | head -1)" | grep 'CTXVERSION\|QuoteEntitiesMapping\|QuoteLineItem' | sed 's/^/CT /'
