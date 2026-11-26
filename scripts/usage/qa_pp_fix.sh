#!/usr/bin/env bash
# CHANGES QA pricing: version 4 "Mindbody line term from quote" now sets the term on every term-defined line; deactivates v4, deploys, reactivates v4, syncs
export VER=4; R=$(pwd); T=$(mktemp -d); cd $T; sf project generate --name p >/dev/null 2>&1; cd p
sf project retrieve start --metadata "ExpressionSetDefinition:RLM_DefaultPricingProcedure" --target-org target --json >/dev/null 2>&1
F=$(find . -name 'RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml' | head -1)
mkdir -p d/expressionSetDefinition; python3 "$R/scripts/usage/py/qa_pp_fix.py" "$F" d/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml || exit 1
V4=$(sf data query --query "SELECT Id FROM ExpressionSetVersion WHERE ExpressionSet.ApiName = 'RLM_DefaultPricingProcedure' AND VersionNumber = 4" --target-org target --json | jq -r '.result.records[0].Id')
echo "deactivate: $(sf data update record --sobject ExpressionSetVersion --record-id $V4 --values 'IsActive=false' --target-org target --json | jq -c '{status, message}')"
sf project deploy start --source-dir d --target-org target --wait 30 --json > r.json 2>&1
echo "DEPLOY $(jq -c '{status: .result.status, errors: [.result.details.componentFailures? | if type=="array" then .[] else . end | .problem?]}' r.json 2>/dev/null | head -c 800)"
cd "$R"; ./scripts/usage/activate_version.sh 4
