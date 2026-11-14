#!/usr/bin/env bash
# READ-ONLY QA for MB-CR-11 Region vs price book.
set -uo pipefail
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
echo "== REGION FLOWS"; raw "SELECT ApiName, Label, TriggerType, TriggerObjectOrEventLabel, IsActive FROM FlowDefinitionView WHERE Label LIKE '%PriceBook%' OR Label LIKE '%Price Book%' OR Label LIKE '%Currency%' OR Label LIKE '%Region%'"
for f in $(sf data query --query "SELECT ApiName FROM FlowDefinitionView WHERE IsActive = true AND (Label LIKE '%PriceBook%' OR Label LIKE '%Price Book%' OR Label LIKE '%Currency%' OR Label LIKE '%Region%')" --target-org target --json | jq -r '.result.records[].ApiName'); do
  FLOW=$f ./scripts/qa/qa_cr07.sh | grep -v "OTHER VERSIONS"
done
echo "== VALIDATION RULES QUOTE/OPP"; raw "SELECT EntityDefinition.QualifiedApiName, ValidationName, Active, ErrorMessage FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Quote','Opportunity','QuoteLineItem')" "--use-tooling-api"
echo "== FLOWS ON QUOTE"; raw "SELECT ApiName, Label, TriggerType, IsActive FROM FlowDefinitionView WHERE TriggerObjectOrEventLabel = 'Quote'"
