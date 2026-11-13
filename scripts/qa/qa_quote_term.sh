#!/usr/bin/env bash
# READ-ONLY: where the TAM 12-month rule lives and which Quote field holds the term.
set -uo pipefail
API="/services/data/v$ORG_API"
echo "== QUOTE TERM FIELDS"; sf api request rest "$API/sobjects/Quote/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Term|Month|Duration";"i")) | {name, label, type, picklist: [.picklistValues[]?.value]}]'
echo "== VALIDATION RULES mentioning Technical / term"; sf data query --use-tooling-api --query "SELECT Id, EntityDefinition.QualifiedApiName, ValidationName, Active, ErrorMessage FROM ValidationRule WHERE ErrorMessage LIKE '%Technical%' OR ErrorMessage LIKE '%term%'" --target-org target --json | jq -c '[.result.records[]? | {obj: .EntityDefinition.QualifiedApiName, name: .ValidationName, active: .Active, msg: .ErrorMessage}]'
echo "== EMPTY QA QUOTES"; sf data query --query "SELECT Id, Name, (SELECT Id FROM QuoteLineItems) FROM Quote WHERE Name LIKE 'QA MR-75%'" --target-org target --json | jq -c '[.result.records[]? | {Id, Name, lines: (.QuoteLineItems.totalSize // 0)}]'
