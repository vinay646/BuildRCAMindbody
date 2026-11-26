#!/usr/bin/env bash
# Read-only: active state of the quote date/term flows in the target org
sf data query --query "SELECT ApiName, IsActive, LastModifiedDate FROM FlowDefinitionView WHERE ApiName LIKE 'MB_Quote%' OR ApiName LIKE 'Update_Quote_Line%' OR ApiName LIKE '%Subscription_Term%' OR ApiName LIKE '%End_Date%' ORDER BY ApiName" --target-org target --json | jq -r '.result.records[] | "\(.ApiName) | active=\(.IsActive) | \(.LastModifiedDate[0:16])"'
