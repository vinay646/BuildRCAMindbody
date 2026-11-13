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
ACC=$(q "SELECT Id FROM Account WHERE Name LIKE 'Usage Backdated Test%' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id // empty')
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
  ACC=$(sf data create record --sobject Account --values "Name='Usage Backdated Test $STAMP' CurrencyIsoCode=USD Payer_Type__c=Self-Pay Account_Level__c=Corporate BillingStreet='1 Test Way' BillingCity=Irvine BillingState=California BillingPostalCode=92618 BillingCountry='United States' ShippingStreet='1 Test Way' ShippingCity=Irvine ShippingState=California ShippingPostalCode=92618 ShippingCountry='United States'" --target-org target --json | jq -r '.result.id')
  CON=$(sf data create record --sobject Contact --values "FirstName=Usage LastName=Backdated Email=usage.backdated@example.com AccountId=$ACC" --target-org target --json | jq -r '.result.id')
  OPP=$(sf data create record --sobject Opportunity --values "Name='Usage Backdated Test $STAMP' AccountId=$ACC StageName=Prospecting CloseDate=$START Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
  echo "account=$ACC contact=$CON opp=$OPP product=$PROD pbe=$PBE"
  BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg prod "$PROD" --arg pbe "$PBE" --arg d "$START" --arg e "$END" --arg con "$CON" '{
    pricingPref: "System", catalogRatesPref: "Skip", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
    graph: {graphId: "backdated", records: [
      {referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: "Usage Backdated Test", OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con,
        BillingStreet: "1 Test Way", BillingCity: "Irvine", BillingState: "California", BillingPostalCode: "92618", BillingCountry: "United States",
        ShippingStreet: "1 Test Way", ShippingCity: "Irvine", ShippingState: "California", ShippingPostalCode: "92618", ShippingCountry: "United States"}},
      {referenceId: "l1", record: {attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}", Product2Id: $prod,
        PricebookEntryId: $pbe, Quantity: 1, StartDate: $d, EndDate: $e, PeriodBoundary: "Anniversary", BillingFrequency: "Monthly"}}]}}')
  rest POST /connect/rev/sales-transaction/actions/place "$BODY" | head -c 1200; echo
  QUOTE=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' LIMIT 1" | jq -r '.[0].Id // empty'); echo "quote=$QUOTE"; [ -z "$QUOTE" ] && exit 1
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
*) show ;;
esac
