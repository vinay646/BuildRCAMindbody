#!/usr/bin/env bash
# CREATES test data: fresh account, Cloud Storage order backdated so its first usage period has closed,
# usage in that period, usage summary job, then an on-demand invoice.
# DEPLOY_PATH: backdated-usage:setup | backdated-usage:summary | backdated-usage:invoice | backdated-usage:check
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
mk() { sf api request rest "$API/sobjects/$1" --method POST --header "Sforce-Duplicate-Rule-Header: allowSave=true" --body "$2" --target-org target 2>&1 | tee mk.json | jq -r '.id // empty'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
PHASE=${DEPLOY_PATH#*:}; PCODE=CS-25Gb
START=2026-10-11; END=2027-10-10; [ "$PHASE" = "setup-today" ] && { START=$(date -u +%Y-%m-%d); END=$(date -u -d "+1 year -1 day" +%Y-%m-%d); PHASE=setup; }; USAGE_AT=2026-10-20T15:00:00Z; QTY=${QTY:-50}
ACC=$(q "SELECT Id FROM Account WHERE Name LIKE 'UsageTrial-%' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id // empty')
show() {
  echo "ACCOUNT $(q "SELECT Id, Name FROM Account WHERE Id = '$ACC'")"
  echo "ORDERS $(q "SELECT Id, OrderNumber, Status, EffectiveDate FROM Order WHERE AccountId = '$ACC'")"
  echo "ASSETS $(q "SELECT Id, Name, LifecycleStartDate, LifecycleEndDate FROM Asset WHERE AccountId = '$ACC'")"
  echo "BILLING SCHEDULES $(q "SELECT Id, BillingScheduleNumber, BillingMethod, BillingType, UnitPrice, TotalAmount, NextBillingDate, NextChargeFromDate, BillingScheduleStartDate, BillingScheduleEndDate, Status FROM BillingSchedule WHERE BillingAccountId = '$ACC'")"
  echo "USAGE ENTITLEMENTS $(q "SELECT Name, EntitlementProcessingStatus FROM TransactionUsageEntitlement WHERE AccountId = '$ACC'") CONTRACTS $(q "SELECT ContractNumber, Status FROM Contract WHERE AccountId = '$ACC'")"
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
  STAMP=$(date -u +%m%d-%H%M); R=$((RANDOM % 9000 + 1000))
  [ -n "$ACC" ] && [ "$(q "SELECT COUNT(Id) n FROM Order WHERE AccountId = '$ACC'" | jq -r '.[0].n')" != "0" ] && ACC=""
  [ -n "$ACC" ] && [ "$(q "SELECT COUNT(Id) n FROM Order WHERE AccountId = '$ACC'" | jq -r '.[0].n')" != "0" ] && ACC=""
  [ -z "$ACC" ] && ACC=$(mk Account "$(jq -nc --arg n "UsageTrial-$STAMP-$R" --arg st "$R Elm Street" '{Name: $n, CurrencyIsoCode: "USD", Payer_Type__c: "Self-Pay", Account_Level__c: "Corporate", BillingStreet: $st, BillingCity: "Austin", BillingState: "Texas", BillingPostalCode: "73301", BillingCountry: "United States", ShippingStreet: $st, ShippingCity: "Austin", ShippingState: "Texas", ShippingPostalCode: "73301", ShippingCountry: "United States"}')")
  [ -z "$ACC" ] && { echo "ACCOUNT ERROR $(head -c 1500 mk.json)"; exit 1; }
  CON=$(q "SELECT Id FROM Contact WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id // empty')
  [ -z "$CON" ] && CON=$(mk Contact "$(jq -nc --arg a "$ACC" --arg r "$R" '{FirstName: ("Trial" + $r), LastName: ("Payer" + $r), Email: ("trial" + $r + "@example.org"), AccountId: $a}')")
  [ -z "$CON" ] && { echo "CONTACT ERROR $(head -c 1500 mk.json)"; exit 1; }
  OPP=$(sf data create record --sobject Opportunity --values "Name='UsageTrial-$STAMP-$R' AccountId=$ACC StageName=Prospecting CloseDate=$START Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
  echo "account=$ACC contact=$CON opp=$OPP product=$PROD pbe=$PBE"
  BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg prod "$PROD" --arg pbe "$PBE" --arg d "$START" --arg e "$END" --arg con "$CON" --arg r "$R" '{
    pricingPref: "System", catalogRatesPref: "Fetch", configurationPref: {configurationMethod: "System"},
    graph: {graphId: "backdated", records: [
      {referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: "Usage Backdated Test", OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con,
        BillingStreet: ($r + " Elm Street"), BillingCity: "Austin", BillingState: "Texas", BillingPostalCode: "73301", BillingCountry: "United States",
        ShippingStreet: ($r + " Elm Street"), ShippingCity: "Austin", ShippingState: "Texas", ShippingPostalCode: "73301", ShippingCountry: "United States"}},
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
usage)
  ASSET=$(q "SELECT Id FROM Asset WHERE AccountId = '$ACC' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id')
  UR=$(q "SELECT UsageResourceId, UsageResource.DefaultUnitOfMeasureId FROM ProductUsageResource WHERE Product.ProductCode = '$PCODE' AND Status = 'Active' LIMIT 1")
  URID=$(echo "$UR" | jq -r '.[0].UsageResourceId'); UOM=$(echo "$UR" | jq -r '.[0].UsageResource.DefaultUnitOfMeasureId')
  NOW=$(date -u +%Y-%m-%dT%H:00:00Z); echo "asset=$ASSET resource=$URID at=$NOW qty=$QTY"
  sf data create record --sobject TransactionJournal --values "AccountId=$ACC ReferenceRecordId=$ASSET UsageResourceId=$URID QuantityUnitOfMeasureId=$UOM Quantity=$QTY UsageType=UsageManagement Status=Pending ActivityDate=$NOW StartDate=$NOW EndDate=$NOW" --target-org target --json | jq -c '{status, id: .result.id, message}'
  ;&
summary)
  echo "== Create Liable Summary"; rest POST /actions/custom/dataProcessingEngineAction/Create_Liable_Summary_v4 '{"inputs":[{}]}' | jq -c '.[0] | {isSuccess, errors, outputValues}' 2>/dev/null; sleep 180
  echo "UEA AFTER LIABLE $(q "SELECT Name, BillingPeriodStartDateTime, BillingPeriodEndDateTime FROM UsageEntitlementAccount WHERE AccountId = '$ACC'")"
  echo "== Create Usage Summary"; rest POST /actions/custom/dataProcessingEngineAction/Create_Usage_Summary_v4 '{"inputs":[{}]}' | jq -c '.[0] | {isSuccess, errors, outputValues}' 2>/dev/null; sleep 240
  show ;;
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
compare)
  NEWO=$(q "SELECT Id FROM Order WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id')
  for O in 801hm00000Aj5XFAAZ $NEWO; do
    echo "---- order $O"
    echo "ORDER $(sf data query --query "SELECT FIELDS(ALL) FROM Order WHERE Id = '$O' LIMIT 1" --target-org target --json | jq -c '[.result.records[] | del(.attributes) | with_entries(select(.value != null and .value != false and .value != 0))]')"
    echo "ITEMS $(sf data query --query "SELECT FIELDS(ALL) FROM OrderItem WHERE OrderId = '$O' LIMIT 20" --target-org target --json | jq -c '[.result.records[] | del(.attributes) | with_entries(select(.value != null and .value != false and .value != 0))]')"
    QID=$(q "SELECT QuoteId FROM Order WHERE Id = '$O'" | jq -r '.[0].QuoteId')
    echo "QUOTE LINES $(sf data query --query "SELECT FIELDS(ALL) FROM QuoteLineItem WHERE QuoteId = '$QID' LIMIT 20" --target-org target --json | jq -c '[.result.records[] | del(.attributes) | with_entries(select(.value != null and .value != false and .value != 0))]')"
  done ;;
steps)
  for P in 13Vhm000000Dl2jEAC 13Vhm000000Du1BEAS; do
    echo "---- plan $P"
    sf data query --query "SELECT FIELDS(ALL) FROM FulfillmentStep WHERE FulfillmentPlanId = '$P' LIMIT 50" --target-org target --json | jq -c '.result.records[]? | del(.attributes) | with_entries(select(.value != null and .value != false and (.key|test("Created|Modified|Stamp|Viewed|Referenced|Owner|IsDeleted")|not)))' | cut -c1-600
    sf data query --query "SELECT FIELDS(ALL) FROM FulfillmentPlan WHERE Id = '$P' LIMIT 1" --target-org target --json | jq -c '.result.records[]? | {Status, Name}'
  done
  echo "CONTRACTS $(q "SELECT Id, ContractNumber, Status, AccountId, StartDate, EndDate FROM Contract WHERE AccountId IN ('001hm00000AiysLAAR', '$ACC')")" ;;
dpe)
  A=$(q "SELECT Id FROM Asset WHERE AccountId = '$ACC' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id')
  echo "UEA $(q "SELECT Name, EffectiveStartDateTime, BillingPeriodStartDateTime, BillingPeriodEndDateTime FROM UsageEntitlementAccount WHERE GrantBindingTargetId = '$A'")"
  echo "BUCKETS $(q "SELECT Name, BucketBalance FROM UsageEntitlementBucket WHERE TransactionUsageEntitlement.AssetId = '$A'")"
  echo "POLICIES $(q "SELECT Name, UsageAggregationPolicyId, RatingFrequencyPolicyId FROM BindingObjUsageRsrcPlcy WHERE BindingObjectId = '$A'")"
  echo "ASSET RATE CARD ENTRIES $(q "SELECT Name, RateCard.Name FROM AssetRateCardEntry WHERE AssetId = '$A'")"
  echo "DPE ACTIONS $(rest GET /actions/custom/dataProcessingEngineAction | jq -c '[.actions[]? | .name]')"
  echo "DPE DEFINITIONS $(sf data query --use-tooling-api --query "SELECT DeveloperName, MasterLabel FROM BatchCalcJobDefinition" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | .DeveloperName]')"
  echo "RECENT JOBS $(q "SELECT Id, Status, CreatedDate FROM BatchJob ORDER BY CreatedDate DESC LIMIT 4")"
  echo "RECENT PARTS $(q "SELECT BatchJob.Id, Name, Status, InputRecordCount, OutputRecordCount, FailedRecordCount FROM BatchJobPart WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 14" | jq -c '[.[] | {j: .BatchJob.Id, n: .Name, s: .Status, i: .InputRecordCount, o: .OutputRecordCount, f: .FailedRecordCount}]')"
  echo "OLD SUMMARY CREATORS $(q "SELECT Name, CreatedById, CreatedBy.Name, CreatedDate FROM UsageSummary ORDER BY CreatedDate LIMIT 3")" ;;
empty)
  echo "EMPTY SUMMARY PARTS $(q "SELECT Id, Name, Status, BatchJobId, InputRecordCount, OutputRecordCount, FailedRecordCount, CreatedDate FROM BatchJobPart WHERE Name LIKE '%Empty%' ORDER BY CreatedDate DESC LIMIT 6")"
  echo "EMPTY SUMMARY JOBS $(q "SELECT Id, Status, CreatedDate, CompletedDate FROM BatchJob WHERE Id IN (SELECT BatchJobId FROM BatchJobPart WHERE Name LIKE '%Empty%') ORDER BY CreatedDate DESC LIMIT 4" 2>&1 | head -c 800)"
  echo "FAILED RECORDS $(q "SELECT BatchJobPart.Name, ErrorCode, ErrorMessage, RecordId, CreatedDate FROM BatchJobPartFailedRecord ORDER BY CreatedDate DESC LIMIT 6")"
  echo "PART NAMES TODAY $(q "SELECT Name FROM BatchJobPart WHERE CreatedDate = TODAY" | jq -c '[.[].Name] | unique')"
  echo "UEA $(q "SELECT Id, Name, BillingPeriodStartDateTime, CreatedDate FROM UsageEntitlementAccount WHERE AccountId = '$ACC'")" ;;
*) show ;;
esac
