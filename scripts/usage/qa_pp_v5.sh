#!/usr/bin/env bash
# CHANGES QA pricing: builds RLM_DefaultPricingProcedure next version (= active + "Mindbody line term from quote" first step), deploys it as Draft; ACTIVATE=1 also activates it
R=$(pwd); T=$(mktemp -d); cd $T; sf project generate --name p >/dev/null 2>&1; cd p
sf project retrieve start --metadata "ExpressionSetDefinition:RLM_DefaultPricingProcedure" --target-org target --json >/dev/null 2>&1
F=$(find . -name 'RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml' | head -1)
mkdir -p d/expressionSetDefinition; python3 "$R/scripts/usage/py/qa_pp_v5.py" "$F" d/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml "${DT:-Numeric}"
sf project deploy start --source-dir d --target-org target --wait 30 --json > r.json 2>&1
echo "DEPLOY $(jq -c '{status: .result.status, success: .result.success, errors: [.result.details.componentFailures? | if type=="array" then .[] else . end | .problem?] }' r.json 2>/dev/null | head -c 1500)"
cd "$R"; echo "VERSIONS $(sf data query --query "SELECT VersionNumber, IsActive FROM ExpressionSetVersion WHERE ExpressionSet.ApiName = 'RLM_DefaultPricingProcedure' ORDER BY VersionNumber" --target-org target --json | jq -c '[.result.records[] | [.VersionNumber, .IsActive]]')"
