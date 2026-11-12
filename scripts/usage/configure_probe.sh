#!/usr/bin/env bash
# Probe: run the product configurator on the latest Pulse quote and print messages / recommendations
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '.result.records // []'; }
QUOTE=$(q "SELECT Id FROM Quote WHERE MB_Prior_System__c = 'Vagaro' ORDER BY LastModifiedDate DESC LIMIT 1" | jq -r '.[0].Id')
LINE=$(q "SELECT Id, Product2.ProductCode FROM QuoteLineItem WHERE QuoteId = '$QUOTE' AND ParentQuoteLineItemId = null AND Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT') LIMIT 1")
echo "quote=$QUOTE line=$LINE"
LID=$(echo "$LINE" | jq -r '.[0].Id // empty')
for body in \
 "{\"transactionId\":\"$QUOTE\",\"transactionLineId\":\"$LID\",\"configuratorOptions\":{\"executePricing\":false,\"executeConfigurationRules\":true,\"returnProductCatalogData\":false,\"validateProductCatalog\":false,\"validateAmendRenewCancel\":false,\"addDefaultConfiguration\":false,\"qualifyAllProductsInTransaction\":false}}" \
 "{\"transactionId\":\"$QUOTE\",\"configuratorOptions\":{\"executePricing\":false,\"executeConfigurationRules\":true}}"; do
  for path in /connect/cpq/configurator/actions/configure /connect/revenue/configurator/actions/configure; do
    echo "== POST $path"
    sf api request rest "$API$path" --method POST --body "$body" --target-org target 2>&1 | head -c 4000; echo
  done
done
