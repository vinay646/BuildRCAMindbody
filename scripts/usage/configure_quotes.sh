#!/usr/bin/env bash
# READ ONLY: run the configurator on the given quote numbers (QN env) and print messages/recommendations
API="/services/data/v$ORG_API"
for n in ${QN:-00000122 00000123 00000124}; do
  id=$(sf data query --query "SELECT Id FROM Quote WHERE QuoteNumber = '$n'" --target-org target --json | jq -r '.result.records[0].Id')
  echo "== $n $id"
  sf api request rest "$API/connect/cpq/configurator/actions/configure" --method POST --body "{\"transactionId\":\"$id\",\"configuratorOptions\":{\"executePricing\":false,\"executeConfigurationRules\":true,\"addDefaultConfiguration\":false,\"validateProductCatalog\":false,\"validateAmendRenewCancel\":false}}" --target-org target 2>&1 \
   | jq -c '{solverStatus, errors, messages, recs: [.productRecommendations[]?.message], ctx: (.transactionContext.SalesTransaction[0] | {Locationcount__c, PriorSystem__c, MbHierarchyLocationCount, MbPriorSystem})}' | cut -c1-1500
done
