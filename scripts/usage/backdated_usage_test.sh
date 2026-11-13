#!/usr/bin/env bash
# CREATES test data: fresh account, Cloud Storage order backdated so its first usage period has closed,
# usage in that period, usage summary job, then an on-demand invoice.
# DEPLOY_PATH: backdated-usage:setup | backdated-usage:summary | backdated-usage:invoice | backdated-usage:check
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
PHASE=${DEPLOY_PATH#*:}; PCODE=CS-25Gb
START=2026-10-11; END=2027-10-10; USAGE_AT=2026-10-20T15:00:00Z; QTY=${QTY:-50}
ACC=$(q "SELECT Id FROM Account WHERE Name LIKE 'Cloud Usage Trial%' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id // empty')
show() {
  echo "ACCOUNT $(q "SELECT Id, Name FROM Account WHERE Id = '$ACC'")"
  echo "ORDERS $(q "SELECT Id, OrderNumber, Status, EffectiveDate FROM Order WHERE AccountId = '$ACC'")"
  echo "ASSETS $(q "SELECT Id, Name, LifecycleStartDate, LifecycleEndDate FROM Asset WHERE AccountId = '$ACC'")"
  echo "BILLING SCHEDULES $(q "SELECT Id, BillingScheduleNumber, BillingMethod, BillingType, UnitPrice, TotalAmount, NextBillingDate, NextChargeFromDate, BillingScheduleStartDate, BillingScheduleEndDate, Status FROM BillingSchedule WHERE BillingAccountId = '$ACC'")"
  echo "JOURNALS $(q "SELECT Name, Quantity, Status, ActivityDate, ReferenceRecordId FROM TransactionJournal WHERE AccountId = '$ACC'")"
  echo "USAGE SUMMARIES $(q "SELECT Name, Status, ConsumptionUnits, DebitedUnits, OverageUnits, StartDateTime, EndDateTime FROM UsageSummary WHERE AccountId = '$ACC' ORDER BY StartDateTime")"
  echo "RATABLE SUMMARIES $(q "SELECT Name, Status, OverageQuantity, NetUnitRate, TotalAmount, StartDateTime, EndDateTime, RatingDecisionDateTime FROM UsageRatableSummary WHERE AccountId = '$ACC' ORDER BY StartDateTime")"
  echo "USAGE BILLING PERIOD ITEMS $(q "SELECT UsageBillingPeriodItemNum, Status, TotalUsedQuantity, OverageQuantity, OverageAmount, StartDateTime, EndDateTime FROM UsageBillingPeriodItem WHERE AccountId = '$ACC' ORDER BY StartDateTime")"
  echo "BILLING PERIOD ITEMS $(q "SELECT BillingPeriodItemNumber, BillingSchedule.BillingScheduleNumber, BillingPeriodStartDate, BillingPeriodEndDate, Amount, Status, InvoiceId FROM BillingPeriodItem WHERE BillingSchedule.BillingAccountId = '$ACC' ORDER BY BillingPeriodStartDate")"
  echo "INVOICES $(q "SELECT Id, DocumentNumber, Status, InvoiceDate, TotalAmount, TotalTaxAmount, TotalAmountWithTax FROM Invoice WHERE BillingAccountId = '$ACC'")"
  echo "INVOICE LINES $(q "SELECT Invoice.DocumentNumber, Name, Type, IsUsageBasedInvoiceLine, Quantity, UnitPrice, ChargeAmount, TaxAmount, InvoiceLineStartDate, InvoiceLineEndDate FROM InvoiceLine WHERE Invoice.BillingAccountId = '$ACC' ORDER BY InvoiceLineStartDate")"
  echo "FAILED BATCH RECORDS $(q "SELECT BatchJobPart.Name, ErrorCode, ErrorMessage, RecordId FROM BatchJobPartFailedRecord WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 6")"
}
case "$PHASE" in
setup)
  PB=$(q "SELECT Id FROM Pricebook2 WHERE IsStandard = true" | jq -r '.[0].Id')
  PROD=$(q "SELECT Id FROM Product2 WHERE ProductCode = '$PCODE'" | jq -r '.[0].Id')
  PBE=$(q "SELECT Id FROM PricebookEntry WHERE Product2Id = '$PROD' AND Pricebook2Id = '$PB' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1" | jq -r '.[0].Id')
  STAMP=$(date -u +%m%d-%H%M)
  [ -n "$ACC" ] && [ "$(q "SELECT COUNT(Id) n FROM Order WHERE AccountId = '$ACC'" | jq -r '.[0].n')" != "0" ] && ACC=""
  [ -z "$ACC" ] && ACC=$(sf data create record --sobject Account --values "Name='Cloud Usage Trial $STAMP' CurrencyIsoCode=USD Payer_Type__c=Self-Pay Account_Level__c=Corporate BillingStreet='200 Demo Avenue' BillingCity=Austin BillingState=Texas BillingPostalCode=73301 BillingCountry='United States' ShippingStreet='200 Demo Avenue' ShippingCity=Austin ShippingState=Texas ShippingPostalCode=73301 ShippingCountry='United States'" --target-org target --json | tee acc.json | jq -r '.result.id // empty')
  [ -z "$ACC" ] && { echo "ACCOUNT ERROR $(jq -c '{message, name, data}' acc.json | head -c 1500)"; exit 1; }
  CON=$(q "SELECT Id FROM Contact WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id // empty')
  [ -z "$CON" ] && CON=$(sf data create record --sobject Contact --values "FirstName=Cloud LastName=Trialist Email=cloud.trialist@example.org AccountId=$ACC" --target-org target --json | tee con.json | jq -r '.result.id // empty')
  [ -z "$CON" ] && { echo "CONTACT ERROR $(jq -c '{message, name}' con.json)"; exit 1; }
  OPP=$(sf data create record --sobject Opportunity --values "Name='Cloud Usage Trial $STAMP' AccountId=$ACC StageName=Prospecting CloseDate=$START Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
  echo "account=$ACC contact=$CON opp=$OPP product=$PROD pbe=$PBE"
  BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg prod "$PROD" --arg pbe "$PBE" --arg d "$START" --arg e "$END" --arg con "$CON" '{
    pricingPref: "System", catalogRatesPref: "Fetch", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
    graph: {graphId: "backdated", records: [
      {referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: "Usage Backdated Test", OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con,
        BillingStreet: "200 Demo Avenue", BillingCity: "Austin", BillingState: "Texas", BillingPostalCode: "73301", BillingCountry: "United States",
        ShippingStreet: "200 Demo Avenue", ShippingCity: "Austin", ShippingState: "Texas", ShippingPostalCode: "73301", ShippingCountry: "United States"}},
      {referenceId: "l1", record: {attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}", Product2Id: $prod,
        PricebookEntryId: $pbe, Quantity: 1, StartDate: $d, EndDate: $e, PeriodBoundary: "Anniversary", BillingFrequency: "Monthly"}}]}}')
  rest POST /connect/rev/sales-transaction/actions/place "$BODY" | head -c 1200; echo
  QUOTE=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' LIMIT 1" | jq -r '.[0].Id // empty'); echo "quote=$QUOTE"; [ -z "$QUOTE" ] && exit 1
  QLI=$(q "SELECT Id FROM QuoteLineItem WHERE QuoteId = '$QUOTE' LIMIT 1" | jq -r '.[0].Id')
  echo "QUOTE LINE RATE CARDS new $(q "SELECT COUNT(Id) n FROM QuoteLineRateCardEntry WHERE QuoteLineItemId = '$QLI'" 2>&1 | head -c 300) old $(q "SELECT COUNT(Id) n FROM QuoteLineRateCardEntry WHERE QuoteLineItemId = '0QLhm0000009XBFGA2'" 2>&1 | head -c 300)"
  sleep 10
  rest POST /actions/standard/createOrderFromQuote "{\"inputs\":[{\"quoteRecordId\":\"$QUOTE\"}]}" | head -c 800; echo
  sleep 15
  OID=$(q "SELECT Id FROM Order WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id // empty'); echo "order=$OID"; [ -z "$OID" ] && exit 1
  echo "ORDER ITEM DATES $(q "SELECT ServiceDate, EndDate, NetUnitPrice FROM OrderItem WHERE OrderId = '$OID'")"
  sf data update record --sobject Order --record-id "$OID" --values "Status=Activated" --target-org target --json | jq -c '{status, message}'
  sleep 90
  ASSET=$(q "SELECT Id FROM Asset WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id // empty'); echo "asset=$ASSET"
  if [ -n "$ASSET" ]; then
    UR=$(q "SELECT UsageResourceId, UsageResource.DefaultUnitOfMeasureId FROM ProductUsageResource WHERE ProductId = '$PROD' AND Status = 'Active' LIMIT 1")
    URID=$(echo "$UR" | jq -r '.[0].UsageResourceId'); UOM=$(echo "$UR" | jq -r '.[0].UsageResource.DefaultUnitOfMeasureId')
    sf data create record --sobject TransactionJournal --values "AccountId=$ACC ReferenceRecordId=$ASSET UsageResourceId=$URID QuantityUnitOfMeasureId=$UOM Quantity=$QTY UsageType=UsageManagement Status=Pending ActivityDate=$USAGE_AT StartDate=$USAGE_AT EndDate=$USAGE_AT" --target-org target --json | jq -c '{status, id: .result.id, message}'
  fi
  show ;;
summary)
  rest POST /actions/custom/dataProcessingEngineAction/Create_Usage_Summary_v4 '{"inputs":[{}]}' | head -c 800; echo
  sleep 300; show ;;
invoice)
  BS=$(q "SELECT Id FROM BillingSchedule WHERE BillingAccountId = '$ACC'" | jq -c '[.[].Id]')
  echo "schedules=$BS"
  BODY=$(jq -nc --argjson ids "$BS" --arg d "$(date -u +%Y-%m-%d)" '{billingScheduleIds: $ids, action: "Draft", invoiceDate: $d, targetDate: $d}')
  rest POST /commerce/invoicing/invoices/collection/actions/generate "$BODY" | head -c 1500; echo
  sleep 120; show ;;
diag)
  OLD=02ihm000000ENuPAAW; NEW=$(q "SELECT Id FROM Asset WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id')
  for A in $OLD $NEW; do
    echo "---- asset $A"
    echo "TUE $(q "SELECT Name, EntitlementQuantity, EntitlementProcessingStatus, CreatedDate FROM TransactionUsageEntitlement WHERE AssetId = '$A'")"
    echo "UEA $(q "SELECT Name, EffectiveStartDateTime, EffectiveEndDateTime, BillingPeriodStartDateTime, BillingPeriodEndDateTime, CreatedDate FROM UsageEntitlementAccount WHERE GrantBindingTargetId = '$A'")"
    echo "BUCKETS $(q "SELECT Name, BucketBalance, CreatedDate FROM UsageEntitlementBucket WHERE TransactionUsageEntitlement.AssetId = '$A'")"
    echo "POLICIES $(q "SELECT Name, UsageResource.Name, CreatedDate FROM BindingObjUsageRsrcPlcy WHERE BindingObjectId = '$A'")"
    echo "ASSET RATE CARD ENTRIES $(q "SELECT Name, RateCard.Name, CreatedDate FROM AssetRateCardEntry WHERE AssetId = '$A'")"
    echo "ASSET ACTIONS $(q "SELECT Id, Type, ActionDate, CreatedDate FROM AssetAction WHERE AssetId = '$A'")"
  done
  echo "ORDER ITEMS old vs new $(q "SELECT Order.OrderNumber, ServiceDate, EndDate, Product2.ProductCode FROM OrderItem WHERE OrderId IN ('801hm00000Aj5XFAAZ', (SELECT Id FROM Order WHERE AccountId = '$ACC'))" 2>&1 | head -c 300)"
  echo "BATCH JOBS TODAY $(q "SELECT Id, Status, CreatedDate FROM BatchJob WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 5")"
  echo "PARTS TODAY $(q "SELECT Name, Status, InputRecordCount, OutputRecordCount, FailedRecordCount, CreatedDate FROM BatchJobPart WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 25" | jq -c '[.[] | {n: .Name, s: .Status, i: .InputRecordCount, o: .OutputRecordCount, f: .FailedRecordCount}]')"
  echo "ASYNC ERRORS $(q "SELECT ApexClass.Name, Status, ExtendedStatus, CreatedDate FROM AsyncApexJob WHERE CreatedDate = TODAY AND Status = 'Failed' LIMIT 5")"
  show ;;
*) show ;;
esac
