#!/usr/bin/env bash
# Usage test (QuantumBit Database): account -> opportunity -> quote -> order -> activate -> usage records.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '.result.records // []'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
echo "===== 1. activate products"
./scripts/run-apex.sh scripts/usage/activate_qb.apex "Activate QuantumBit Database" || true
PB=$(q "SELECT Id FROM Pricebook2 WHERE IsStandard = true" | jq -r '.[0].Id')
PROD=$(q "SELECT Id FROM Product2 WHERE ProductCode = 'QB-DB'" | jq -r '.[0].Id')
PBE=$(q "SELECT Id, ProductSellingModelId FROM PricebookEntry WHERE Product2Id = '$PROD' AND Pricebook2Id = '$PB' AND CurrencyIsoCode = 'USD' LIMIT 1")
PBEID=$(echo "$PBE" | jq -r '.[0].Id'); PSM=$(echo "$PBE" | jq -r '.[0].ProductSellingModelId')
echo "pricebook=$PB product=$PROD pbe=$PBEID psm=$PSM"
echo "===== 2. account and opportunity"
STAMP=$(date -u +%m%d-%H%M)
ACC=$(sf data create record --sobject Account --values "Name='Usage Test QuantumBit $STAMP' CurrencyIsoCode=USD Payer_Type__c=Self-Pay Account_Level__c=Corporate BillingStreet='1 Test Way' BillingCity=Irvine BillingState=California BillingPostalCode=92618 BillingCountry='United States' ShippingStreet='1 Test Way' ShippingCity=Irvine ShippingState=California ShippingPostalCode=92618 ShippingCountry='United States'" --target-org target --json > acc.json; jq -r '.message // empty' acc.json; jq -r '.result.id' acc.json)
CON=$(sf data create record --sobject Contact --values "FirstName=Usage LastName=Tester Email=usage.tester@example.com AccountId=$ACC" --target-org target --json | jq -r '.result.id')
OPP=$(sf data create record --sobject Opportunity --values "Name='Usage Test QuantumBit $STAMP' AccountId=$ACC StageName=Prospecting CloseDate=$(date -u +%Y-%m-%d) Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
echo "account=$ACC contact=$CON opportunity=$OPP"
echo "===== 3. quote (Place Sales Transaction)"
TODAY=$(date -u +%Y-%m-%d); END=$(date -u -d '+1 year -1 day' +%Y-%m-%d)
BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg prod "$PROD" --arg pbe "$PBEID" --arg d "$TODAY" --arg e "$END" --arg con "$CON" '{
  pricingPref: "System", catalogRatesPref: "Skip", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
  graph: {graphId: "usagetest", records: [
    {referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: "Usage Test QuantumBit", OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con,
      BillingStreet: "1 Test Way", BillingCity: "Irvine", BillingState: "California", BillingPostalCode: "92618", BillingCountry: "United States",
      ShippingStreet: "1 Test Way", ShippingCity: "Irvine", ShippingState: "California", ShippingPostalCode: "92618", ShippingCountry: "United States"}},
    {referenceId: "l1", record: {attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}", Product2Id: $prod,
      PricebookEntryId: $pbe, Quantity: 1, StartDate: $d, EndDate: $e, PeriodBoundary: "Anniversary", BillingFrequency: "Annual"}}]}}')
RES=$(rest POST /connect/rev/sales-transaction/actions/place "$BODY"); echo "$RES" | head -c 1500; echo
QUOTE=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id // empty')
echo "quote=$QUOTE"; [ -z "$QUOTE" ] && exit 0
sleep 10
echo "===== 4. order from quote"
RES=$(rest POST /actions/standard/createOrderFromQuote "{\"inputs\":[{\"quoteRecordId\":\"$QUOTE\"}]}"); echo "$RES" | head -c 1200; echo
sleep 15
ORDER=$(q "SELECT Id, OrderNumber, Status FROM Order WHERE AccountId = '$ACC' ORDER BY CreatedDate DESC LIMIT 1")
echo "order=$ORDER"; OID=$(echo "$ORDER" | jq -r '.[0].Id // empty'); [ -z "$OID" ] && exit 0
echo "===== 5. activate order"
sf data update record --sobject Order --record-id "$OID" --values "Status=Activated" --target-org target --json | jq -c '{status: .status, message: .message}'
sleep 60
echo "===== 6. records created by activation"
echo "ASSETS $(q "SELECT Id, Name, Product2.ProductCode, Status FROM Asset WHERE AccountId = '$ACC'")"
echo "TRANSACTION USAGE ENTITLEMENTS $(q "SELECT Name, UsageResource.Name, EntitlementQuantity, EntitlementProcessingStatus, AssetId FROM TransactionUsageEntitlement WHERE AccountId = '$ACC'")"
echo "USAGE ENTITLEMENT ACCOUNTS $(q "SELECT Name, EffectiveStartDateTime, EffectiveEndDateTime, GrantBindingTargetId FROM UsageEntitlementAccount WHERE AccountId = '$ACC'")"
echo "ASSET RATE CARD ENTRIES $(q "SELECT Name, RateCard.Name, UsageResource.Name, AssetId FROM AssetRateCardEntry WHERE Asset.AccountId = '$ACC'")"
echo "TEST_ACCOUNT=$ACC"
