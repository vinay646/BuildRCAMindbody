#!/usr/bin/env bash
# Read-only: QA fields for prior system and location counts on Opportunity, Quote, Account; picklist values
for o in Opportunity Quote Account; do echo "$o: $(sf sobject describe --sobject $o --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.name|test("Prior|ocation|Active_";"i")) | [.name, .type, ([.picklistValues[]?.value] | join("/"))]]')"; done
