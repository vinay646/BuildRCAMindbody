#!/usr/bin/env bash
# Usage test, part 2: load usage (Transaction Journals) on the test asset and run the Create Usage Summary job.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '.result.records // []'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
ACC=$(q "SELECT Id FROM Account WHERE Name LIKE 'Usage Test QuantumBit%' AND BillingStreet != null ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id')
ASSET=$(q "SELECT Id FROM Asset WHERE AccountId = '$ACC' AND Product2.ProductCode = 'QB-DB' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id')
echo "account=$ACC asset=$ASSET"
CHECK=""; [ "${DEPLOY_PATH:-}" = "check" ] && CHECK=1
if [ "${DEPLOY_PATH:-}" = "rerun" ]; then ./scripts/run-apex.sh scripts/usage/fix_policies.apex "Fix usage policies" || true; fi
if [ -z "$CHECK" ] && [ "${DEPLOY_PATH:-}" != "rerun" ]; then
  echo "===== 1. usage records (Transaction Journals)"
  NOW=$(date -u +%Y-%m-%dT%H:00:00Z); LATER=$(date -u -d '+15 min' +%Y-%m-%dT%H:15:00Z)
  for r in "Compute Time|120" "Data Storage|8"; do
    NAME=${r%|*}; QTY=${r#*|}
    UR=$(q "SELECT Id, DefaultUnitOfMeasureId FROM UsageResource WHERE Name = '$NAME' AND Code LIKE 'UR-%' LIMIT 1")
    URID=$(echo "$UR" | jq -r '.[0].Id'); UOM=$(echo "$UR" | jq -r '.[0].DefaultUnitOfMeasureId')
    sf data create record --sobject TransactionJournal --values "AccountId=$ACC ReferenceRecordId=$ASSET UsageResourceId=$URID QuantityUnitOfMeasureId=$UOM Quantity=$QTY UsageType=UsageManagement Status=Pending ActivityDate=$NOW StartDate=$NOW EndDate=$LATER" --target-org target --json | jq -c '{status, id: .result.id, message}'
    echo "  $NAME: $QTY"
  done
fi
if [ -z "$CHECK" ]; then
echo "===== 2. Create Usage Summary job"
rest GET /actions/custom/dataProcessingEngineAction | jq -c '[.actions[]? | {name, label}]' 2>/dev/null | head -c 1500; echo
rest GET /actions/custom/dataProcessingEngineAction/Create_Usage_Summary_v4 | jq -c '{inputs: [.inputs[]? | {name, type, required}]}' 2>/dev/null | head -c 1500; echo
RES=$(rest POST /actions/custom/dataProcessingEngineAction/Create_Usage_Summary_v4 '{"inputs":[{}]}'); echo "$RES" | head -c 1500; echo
sleep 240
fi
echo "===== 3. results"
echo "BATCH JOBS $(q "SELECT Id, Status, CreatedDate FROM BatchJob ORDER BY CreatedDate DESC LIMIT 3")"
echo "BATCH JOB PARTS $(q "SELECT Name, Status, InputRecordCount, OutputRecordCount, FailedRecordCount FROM BatchJobPart ORDER BY CreatedDate DESC LIMIT 6")"
echo "JOURNALS $(q "SELECT Name, UsageResource.Name, Quantity, Status FROM TransactionJournal WHERE AccountId = '$ACC'")"
echo "USAGE SUMMARIES $(q "SELECT Name, Status, ConsumptionUnits, DebitedUnits, OverageUnits, StartDateTime, EndDateTime, UsageEntitlementBucket.UsageResource.Name FROM UsageSummary WHERE AccountId = '$ACC'")"
echo "BUCKETS $(q "SELECT Name, UsageResource.Name, BucketBalance, TotalConsumedEntitlement, TotalAsOfBalance FROM UsageEntitlementBucket WHERE TransactionUsageEntitlement.AccountId = '$ACC'")"
echo "RATABLE SUMMARIES $(q "SELECT Name, Status, OverageQuantity, StartDateTime, EndDateTime FROM UsageRatableSummary WHERE AccountId = '$ACC'")"
echo "LIABLE / BILLING PERIOD ITEMS $(q "SELECT Name, Status, TotalUsedQuantity, OverageQuantity, OverageAmount FROM UsageBillingPeriodItem WHERE AccountId = '$ACC'")"
echo "LATEST JOB PARTS $(q "SELECT BatchJob.Id, Name, Status, InputRecordCount, OutputRecordCount, FailedRecordCount FROM BatchJobPart ORDER BY CreatedDate DESC LIMIT 12")"
echo "UEA BILLING PERIOD $(q "SELECT Name, BillingPeriodStartDateTime, BillingPeriodEndDateTime, BillingPeriodTerm, BillingPeriodUnit, BillDayOfMonth, EffectiveStartDateTime FROM UsageEntitlementAccount WHERE AccountId = '$ACC'")"
echo "FAILED RECORDS $(q "SELECT BatchJobPart.Name, ErrorCode, ErrorMessage, RecordId FROM BatchJobPartFailedRecord ORDER BY CreatedDate DESC LIMIT 6" 2>&1 | head -c 2500)"
