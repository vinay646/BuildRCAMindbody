#!/usr/bin/env bash
# CREATES test data: Mindbody usage in arrears - account with SMS overage + Marketplace fee order backdated to 11 Oct,
# October usage (2,500 texts; fees 30 + 12.50), usage summary jobs, then an invoice. Phase = $1: setup | summary | invoice | show

set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
mk() { sf api request rest "$API/sobjects/$1" --method POST --header "Sforce-Duplicate-Rule-Header: allowSave=true" --body "$2" --target-org target 2>&1 | tee mk.json | jq -r '.id // empty'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
PHASE=${1:-show}; START=2026-10-11; END=2027-10-10; USAGE_AT=2026-10-20T15:00:00Z
ACC=$(q "SELECT Id FROM Account WHERE Name LIKE 'MBUsage-%' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id // empty')
show() {
  echo "ORDERS $(q "SELECT OrderNumber, Status FROM Order WHERE AccountId = '$ACC'")"
  echo "ASSETS $(q "SELECT Name, Product2.ProductCode FROM Asset WHERE AccountId = '$ACC'")"
  echo "BILLING SCHEDULES $(q "SELECT BillingScheduleNumber, BillingMethod, BillingType, Status, NextBillingDate FROM BillingSchedule WHERE BillingAccountId = '$ACC'")"
  echo "JOURNALS $(q "SELECT Quantity, Status, UsageResource.Code FROM TransactionJournal WHERE AccountId = '$ACC'")"
  echo "USAGE SUMMARIES $(q "SELECT UsageResource.Code, Status, ConsumptionUnits, OverageUnits, StartDateTime FROM UsageSummary WHERE AccountId = '$ACC' ORDER BY StartDateTime")"
  echo "RATABLE SUMMARIES $(q "SELECT Status, OverageQuantity, NetUnitRate, TotalAmount, StartDateTime FROM UsageRatableSummary WHERE AccountId = '$ACC' ORDER BY StartDateTime")"
  echo "BILLING PERIOD ITEMS $(q "SELECT BillingSchedule.BillingScheduleNumber, BillingPeriodStartDate, BillingPeriodEndDate, Amount, Status FROM BillingPeriodItem WHERE BillingSchedule.BillingAccountId = '$ACC' ORDER BY BillingPeriodStartDate LIMIT 6")"
  echo "INVOICES $(q "SELECT DocumentNumber, Status, TotalAmount, TotalTaxAmount, TotalAmountWithTax FROM Invoice WHERE BillingAccountId = '$ACC'")"
  echo "INVOICE LINES $(q "SELECT Name, IsUsageBasedInvoiceLine, Quantity, UnitPrice, ChargeAmount, InvoiceLineStartDate, InvoiceLineEndDate FROM InvoiceLine WHERE Invoice.BillingAccountId = '$ACC'")"
  echo "FAILED BATCH RECORDS $(q "SELECT BatchJobPart.Name, ErrorMessage FROM BatchJobPartFailedRecord WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 4")"
}
case "$PHASE" in
setup)
  PB=$(q "SELECT Id FROM Pricebook2 WHERE IsStandard = true" | jq -r '.[0].Id')
  LE=$(q "SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - US'" | jq -r '.[0].Id')
  BT=$(q "SELECT Id FROM BillingTreatment WHERE Name = 'Mindbody - US - Arrears'" | jq -r '.[0].Id')
  STAMP=$(date -u +%m%d-%H%M); R=$((RANDOM % 9000 + 1000))
  ACC=$(mk Account "$(jq -nc --arg n "MBUsage-$STAMP-$R" --arg st "$R Elm Street" '{Name: $n, CurrencyIsoCode: "USD", BillingStreet: $st, BillingCity: "Austin", BillingState: "Texas", BillingPostalCode: "73301", BillingCountry: "United States", ShippingStreet: $st, ShippingCity: "Austin", ShippingState: "Texas", ShippingPostalCode: "73301", ShippingCountry: "United States"}')")
  [ -z "$ACC" ] && { echo "ACCOUNT ERROR $(head -c 800 mk.json)"; exit 1; }
  CON=$(mk Contact "$(jq -nc --arg a "$ACC" --arg r "$R" '{FirstName: ("Usage" + $r), LastName: ("Payer" + $r), Email: ("mbusage" + $r + "@example.org"), AccountId: $a}')")
  OPP=$(sf data create record --sobject Opportunity --values "Name='MBUsage-$STAMP-$R' AccountId=$ACC StageName=Prospecting CloseDate=$START Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
  LINES='[]'
  for C in MB-SMS MB-MKT; do
    PBE=$(q "SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = '$C' AND Pricebook2Id = '$PB' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1")
    LINES=$(echo "$LINES" | jq -c --argjson p "$PBE" --arg d "$START" --arg le "$LE" --arg bt "$BT" --arg i "$C" '. + [{referenceId: ("l" + ($i | gsub("-";""))), record: {attributes: {type: "QuoteLineItem", method: "POST"}, QuoteId: "@{q1.id}", Product2Id: $p[0].Product2Id, PricebookEntryId: $p[0].Id, Quantity: 1, StartDate: $d, PeriodBoundary: "Anniversary", BillingFrequency: "Monthly", LegalEntityId: $le, BillingTreatmentId: $bt}}]')
  done
  BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg con "$CON" --arg r "$R" --arg le "$LE" --argjson lines "$LINES" '{pricingPref: "System", catalogRatesPref: "Fetch", configurationPref: {configurationMethod: "Skip"}, taxPref: "Skip",
    graph: {graphId: "mbusage", records: ([{referenceId: "q1", record: {attributes: {type: "Quote", method: "POST"}, Name: "MB Usage Arrears Test", OpportunityId: $opp, Pricebook2Id: $pb, BillToContactId: $con, ContactId: $con, LegalEntityId: $le,
      BillingStreet: ($r + " Elm Street"), BillingCity: "Austin", BillingState: "Texas", BillingPostalCode: "73301", BillingCountry: "United States",
      ShippingStreet: ($r + " Elm Street"), ShippingCity: "Austin", ShippingState: "Texas", ShippingPostalCode: "73301", ShippingCountry: "United States"}}] + $lines)}}')
  echo "place: $(rest POST /connect/rev/sales-transaction/actions/place "$BODY" | tr -d '\n' | head -c 400)"
  QUOTE=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP' LIMIT 1" | jq -r '.[0].Id // empty'); [ -z "$QUOTE" ] && exit 1
  echo "QUOTE LINE RATE CARDS $(q "SELECT QuoteLineItem.Product2.ProductCode, Rate FROM QuoteLineRateCardEntry WHERE QuoteLineItem.QuoteId = '$QUOTE'" 2>&1 | head -c 300)"
  sleep 10
  echo "order: $(rest POST /actions/standard/createOrderFromQuote "{\"inputs\":[{\"quoteRecordId\":\"$QUOTE\"}]}" | tr -d '\n' | head -c 300)"
  sleep 15
  OID=$(q "SELECT Id FROM Order WHERE AccountId = '$ACC' LIMIT 1" | jq -r '.[0].Id // empty'); [ -z "$OID" ] && exit 1
  for _ in 1 2 3 4 5 6; do sleep 15; [ "$(q "SELECT Status FROM Order WHERE Id = '$OID'" | jq -r '.[0].Status')" = "Activated" ] && break; done
  [ "$(q "SELECT Status FROM Order WHERE Id = '$OID'" | jq -r '.[0].Status')" != "Activated" ] && echo "activate: $(sf data update record --sobject Order --record-id "$OID" --values "Status=Activated" --target-org target --json | jq -c '{status, message}')"
  sleep 90
  for C in MB-SMS:2500 MB-MKT:30 MB-MKT:12.5; do
    P=${C%%:*}; N=${C#*:}
    A=$(q "SELECT Id FROM Asset WHERE AccountId = '$ACC' AND Product2.ProductCode = '$P' LIMIT 1" | jq -r '.[0].Id // empty')
    UR=$(q "SELECT UsageResourceId, UsageResource.DefaultUnitOfMeasureId FROM ProductUsageResource WHERE Product.ProductCode = '$P' AND Status = 'Active' LIMIT 1")
    [ -n "$A" ] && echo "journal $P $N: $(sf data create record --sobject TransactionJournal --values "AccountId=$ACC ReferenceRecordId=$A UsageResourceId=$(echo "$UR" | jq -r '.[0].UsageResourceId') QuantityUnitOfMeasureId=$(echo "$UR" | jq -r '.[0].UsageResource.DefaultUnitOfMeasureId') Quantity=$N UsageType=UsageManagement Status=Pending ActivityDate=$USAGE_AT StartDate=$USAGE_AT EndDate=$USAGE_AT" --target-org target --json | jq -c '.status, .message')"
  done
  show ;;
summary)
  echo "== Create Liable Summary"; rest POST /actions/custom/dataProcessingEngineAction/Create_Liable_Summary_v4 '{"inputs":[{}]}' | jq -c '.[0] | {isSuccess, errors}' 2>/dev/null; sleep 180
  echo "== Create Usage Summary"; rest POST /actions/custom/dataProcessingEngineAction/Create_Usage_Summary_v4 '{"inputs":[{}]}' | jq -c '.[0] | {isSuccess, errors}' 2>/dev/null; sleep 240
  show ;;
invoice)
  BS=$(q "SELECT Id FROM BillingSchedule WHERE BillingAccountId = '$ACC'" | jq -c '[.[].Id]')
  echo "generate: $(rest POST /commerce/invoicing/invoices/collection/actions/generate "$(jq -nc --argjson ids "$BS" --arg d "$(date -u +%Y-%m-%d)" '{billingScheduleIds: $ids, action: "Draft", invoiceDate: $d, targetDate: $d}')" | tr -d '\n' | head -c 300)"
  sleep 120; show ;;
diag)
  echo "TUE $(q "SELECT UsageResource.Code, EntitlementProcessingStatus FROM TransactionUsageEntitlement WHERE AccountId = '$ACC'")"
  echo "UEA $(q "SELECT Name, EffectiveStartDateTime, BillingPeriodStartDateTime, BillingPeriodEndDateTime FROM UsageEntitlementAccount WHERE AccountId = '$ACC'")"
  echo "POLICIES $(q "SELECT UsageResource.Code, UsageAggregationPolicyId, RatingFrequencyPolicyId, UsageOveragePolicyId FROM BindingObjUsageRsrcPlcy WHERE BindingObjectId IN (SELECT Id FROM Asset WHERE AccountId = '$ACC')")"
  echo "ASSET RATE CARD ENTRIES $(q "SELECT RateCard.Name, UsageResource.Code FROM AssetRateCardEntry WHERE Asset.AccountId = '$ACC'")"
  echo "EMPTY SUMMARY FAILS $(q "SELECT BatchJobPart.Name, ErrorMessage, CreatedDate FROM BatchJobPartFailedRecord ORDER BY CreatedDate DESC LIMIT 3")"
  echo "PARTS TODAY $(q "SELECT Name, Status, InputRecordCount, OutputRecordCount, FailedRecordCount FROM BatchJobPart WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 12" | jq -c '[.[] | [.Name, .Status, .InputRecordCount, .OutputRecordCount, .FailedRecordCount]]')"
  echo "OLD WORKING JOURNAL $(q "SELECT Status, ReferenceRecordId, UsageResource.Code, ActivityDate FROM TransactionJournal WHERE Status = 'Processed' ORDER BY CreatedDate DESC LIMIT 1")"
  ;;
*) show ;;
esac
