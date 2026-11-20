#!/usr/bin/env bash
# Compares the saved Mindbody Plans CML with cml/MindbodyPlans_QA.cml; CHANGES the org (creates links) only when they match.
API="/services/data/v$ORG_API"
id=$(sf data query --use-tooling-api --query "SELECT Id, Status FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName = 'Mindbody_Plans' ORDER BY VersionNumber DESC LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id')
sf api request rest "$API/tooling/sobjects/ExpressionSetDefinitionVersion/$id/ConstraintModel" --target-org target 2>/dev/null | tr -d '\r' > saved.cml
a=$(sed -e '$a\' saved.cml | md5sum | cut -c1-10); b=$(md5sum < cml/MindbodyPlans_QA.cml | cut -c1-10)
echo "version $id: saved $(wc -c < saved.cml) bytes md5 $a | QA file $(wc -c < cml/MindbodyPlans_QA.cml) bytes md5 $b"
if [ "$a" != "$b" ]; then
  echo "DIFFERENT – no links created. Diff (saved vs QA file):"; diff <(sed -e '$a\' saved.cml) cml/MindbodyPlans_QA.cml | head -30; exit 0
fi
python3 scripts/qa_build/cml_links.py
