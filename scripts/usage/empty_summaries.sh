#!/usr/bin/env bash
# Usage test: why runtime_industries_usage__CreateEmptySummaries fails – describe it, run it for the test UEA, read the failures.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
F=runtime_industries_usage__CreateEmptySummaries
ACC=$(q "SELECT Id FROM Account WHERE Name LIKE 'Usage Test QuantumBit%' AND BillingStreet != null ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.result.records[0].Id')
UEA=$(q "SELECT Id FROM UsageEntitlementAccount WHERE AccountId = '$ACC' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.result.records[0].Id')
echo "account=$ACC uea=$UEA"
echo "===== flow inputs"
rest GET "/actions/custom/flow/$F" | jq -c '{label, inputs: [.inputs[]? | {name, type, required, maxOccurs}]}' | head -c 2000; echo
echo "===== objects about batch failures"
rest GET "/sobjects" | jq -r '.sobjects[] | select(.name | test("BatchJob|FlowInterview|FlowExecution"; "i")) | .name' | tr '\n' ' '; echo
echo "===== failed parts (latest) and their failed records"
q "SELECT Id, Name, Status, BatchJobId, InputRecordCount, FailedRecordCount, CreatedDate FROM BatchJobPart WHERE Name LIKE 'Create Empty Summaries%' ORDER BY CreatedDate DESC LIMIT 3" | jq -c '.result.records[] | del(.attributes)'
for o in BatchJobPartFailedRecord; do
  q "SELECT FIELDS(STANDARD) FROM $o ORDER BY CreatedDate DESC LIMIT 5" | jq -c '.result.records // .message' | head -c 3000; echo
done
echo "===== run the flow for the test UEA"
for name in recordIds RecordIds ids Ids recordId usageEntitlementAccountIds; do
  RES=$(rest POST "/actions/custom/flow/$F" "{\"inputs\":[{\"$name\":[\"$UEA\"]}]}")
  echo "input $name: $(echo "$RES" | head -c 1500)"
  echo "$RES" | grep -q '"isSuccess": *true' && break
done
sleep 20
echo "===== summaries after the run"
q "SELECT Name, Status, StartDateTime, EndDateTime, ConsumptionUnits FROM UsageSummary WHERE AccountId = '$ACC'" | jq -c '.result.records // .message'
q "SELECT Name, BillingPeriodStartDateTime, BillingPeriodEndDateTime FROM UsageEntitlementAccount WHERE Id = '$UEA'" | jq -c '.result.records'
