#!/usr/bin/env bash
# Read-only: proration / term-defined branch steps of the org's active RLM_DefaultPricingProcedure
R=$(pwd); T=$(mktemp -d); cd $T; sf project generate --name p >/dev/null 2>&1; cd p
sf project retrieve start --metadata "ExpressionSetDefinition:RLM_DefaultPricingProcedure" --target-org target --json >/dev/null 2>&1
python3 "$R/scripts/usage/py/pp_branches.py" "$(find . -name 'RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml' | head -1)" | sed 's/^/BR /'
