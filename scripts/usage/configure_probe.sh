#!/usr/bin/env bash
# Probe: run the product configurator on the latest Pulse quote and print messages / recommendations
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '.result.records // []'; }
QUOTE=$(q "SELECT Id FROM Quote WHERE MB_Prior_System__c = 'Vagaro' ORDER BY LastModifiedDate DESC LIMIT 1" | jq -r '.[0].Id')
LINE=$(q "SELECT Id, Product2.ProductCode FROM QuoteLineItem WHERE QuoteId = '$QUOTE' AND ParentQuoteLineItemId = null AND Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT') LIMIT 1")
echo "quote=$QUOTE line=$LINE"
echo "ALL LINES $(q "SELECT Product2.ProductCode, ParentQuoteLineItemId, Quantity FROM QuoteLineItem WHERE QuoteId = '$QUOTE'" | jq -c '[.[] | {code: .Product2.ProductCode, parent: .ParentQuoteLineItemId, qty: .Quantity}]')"
if [ -z "$(echo "$LINE" | jq -r '.[0].Id // empty')" ]; then
  echo "== adding Accelerate to the quote (Place Sales Transaction)"
  PB=$(q "SELECT Pricebook2Id FROM Quote WHERE Id = '$QUOTE'" | jq -r '.[0].Pricebook2Id')
  PBE=$(q "SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = '$PB' AND Product2.ProductCode = 'MB-ACC' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1")
  D=$(date -u +%Y-%m-%d); E=$(date -u -d '+1 year -1 day' +%Y-%m-%d)
  BODY=$(jq -nc --arg q "$QUOTE" --arg p "$(echo "$PBE" | jq -r '.[0].Product2Id')" --arg e "$(echo "$PBE" | jq -r '.[0].Id')" --arg d "$D" --arg ed "$E" '{pricingPref:"Skip",catalogRatesPref:"Skip",taxPref:"Skip",configurationPref:{configurationMethod:"System",configurationOptions:{executeConfigurationRules:true,addDefaultConfiguration:true,validateProductCatalog:false,validateAmendRenewCancel:false}},
    graph:{graphId:"addplan",records:[{referenceId:"q",record:{attributes:{type:"Quote",method:"PATCH",id:$q}}},
      {referenceId:"l1",record:{attributes:{type:"QuoteLineItem",method:"POST"},QuoteId:$q,Product2Id:$p,PricebookEntryId:$e,Quantity:1,StartDate:$d,EndDate:$ed,PeriodBoundary:"Anniversary",BillingFrequency:"Monthly"}}]}}')
  sf api request rest "$API/connect/rev/sales-transaction/actions/place" --method POST --body "$BODY" --target-org target 2>&1 | head -c 1500; echo
  sleep 10
  LINE=$(q "SELECT Id, Product2.ProductCode FROM QuoteLineItem WHERE QuoteId = '$QUOTE' AND ParentQuoteLineItemId = null AND Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT') LIMIT 1")
  echo "line now=$LINE"
fi
LID=$(echo "$LINE" | jq -r '.[0].Id // empty')
for body in \
 "{\"transactionId\":\"$QUOTE\",\"transactionLineId\":\"$LID\",\"configuratorOptions\":{\"executePricing\":false,\"executeConfigurationRules\":true,\"returnProductCatalogData\":false,\"validateProductCatalog\":false,\"validateAmendRenewCancel\":false,\"addDefaultConfiguration\":false,\"qualifyAllProductsInTransaction\":false}}" \
 "{\"transactionId\":\"$QUOTE\",\"configuratorOptions\":{\"executePricing\":false,\"executeConfigurationRules\":true}}"; do
  for path in /connect/cpq/configurator/actions/configure /connect/revenue/configurator/actions/configure; do
    echo "== POST $path"
    sf api request rest "$API$path" --method POST --body "$body" --target-org target 2>&1 | head -c 4000; echo
  done
done
