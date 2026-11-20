#!/usr/bin/env bash
# READ ONLY: Mindbody Plans constraint model – versions, CML text of each version, product links, field writability.
API="/services/data/v$ORG_API"
sf data query --use-tooling-api --query "SELECT Id, DeveloperName, VersionNumber, Status, LastModifiedDate FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName = 'Mindbody_Plans' ORDER BY VersionNumber" --target-org target --json | jq -c '.result.records[]? | del(.attributes)'
for id in $(sf data query --use-tooling-api --query "SELECT Id FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName = 'Mindbody_Plans' ORDER BY VersionNumber" --target-org target --json | jq -r '.result.records[]?.Id'); do
  sf api request rest "$API/tooling/sobjects/ExpressionSetDefinitionVersion/$id/ConstraintModel" --target-org target > cml_$id.txt 2>&1
  echo "== CML $id: $(wc -c < cml_$id.txt) bytes, md5 $(md5sum < cml_$id.txt | cut -c1-10), CR-01 constraint present: $(grep -c 'lineitems\[Starter\] + lineitems\[Accelerate\]' cml_$id.txt)"
  echo "----- BEGIN"; cat cml_$id.txt; echo; echo "----- END"
done
echo "== product links: $(sf data query --query "SELECT COUNT() FROM ExpressionSetConstraintObj WHERE ExpressionSet.ApiName = 'Mindbody_Plans'" --target-org target --json | jq -r '.result.totalSize')"
sf api request rest "$API/tooling/sobjects/ExpressionSetDefinitionVersion/describe" --target-org target 2>/dev/null | jq -c '[.fields[] | select(.name=="ConstraintModel" or .name=="Status") | {name, createable, updateable}]'
