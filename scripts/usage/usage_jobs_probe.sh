#!/usr/bin/env bash
# Read-only: usage-related flows/actions and recent Create Empty Summaries batch parts
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
echo "FLOW ACTIONS $(sf api request rest "$API/actions/custom/flow" --target-org target 2>/dev/null | jq -c '[.actions[]?.name | select(test("sage|Summar|Empty|Rating";"i"))]')"
echo "STD ACTIONS $(sf api request rest "$API/actions/standard" --target-org target 2>/dev/null | jq -c '[.actions[]?.name | select(test("sage|Summar|Rating|Liable";"i"))]')"
echo "DPE $(sf api request rest "$API/actions/custom/dataProcessingEngineAction" --target-org target 2>/dev/null | jq -c '[.actions[]?.name]')"
echo "EMPTY PARTS $(q "SELECT Name, Status, InputRecordCount, OutputRecordCount, FailedRecordCount, CreatedDate FROM BatchJobPart WHERE Name LIKE '%mpty%' ORDER BY CreatedDate DESC LIMIT 4")"
echo "BATCH JOB DEFS $(q "SELECT DeveloperName, Type FROM BatchJobDefinition" 2>&1 | head -c 600)"
