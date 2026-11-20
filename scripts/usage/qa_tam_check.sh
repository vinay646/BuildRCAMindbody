#!/usr/bin/env bash
# READ ONLY: TAM rule (CR-12) in QA – active CML context path + configurator result on 12/30-location quotes
API="/services/data/v$ORG_API"
v=$(sf data query --use-tooling-api --query "SELECT Id, VersionNumber, Status FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName = 'Mindbody_Plans' ORDER BY VersionNumber DESC" --target-org target --json | jq -r '.result.records[] | "\(.Id) v\(.VersionNumber) \(.Status)"')
echo "$v"
for id in $(echo "$v" | awk '{print $1}'); do echo "$id: $(sf api request rest "$API/tooling/sobjects/ExpressionSetDefinitionVersion/$id/ConstraintModel" --target-org target 2>/dev/null | grep -n 'contextPath\|TechnicalAccountManagement ==\|>= 10' | tr '\n' ' ' | cut -c1-500)"; done
for n in 00000124 00000123; do
  id=$(sf data query --query "SELECT Id FROM Quote WHERE QuoteNumber = '$n'" --target-org target --json | jq -r '.result.records[0].Id')
  sf api request rest "$API/connect/cpq/configurator/actions/configure" --method POST --body "{\"transactionId\":\"$id\",\"configuratorOptions\":{\"executePricing\":false,\"executeConfigurationRules\":true}}" --target-org target 2>&1 \
   | jq -c --arg n $n '{q: $n, loc: .transactionContext.SalesTransaction[0].Locationcount__c, msgs: [.messages[]?[]?.message], recs: [.productRecommendations[]?.message], errors}' | cut -c1-600
done
