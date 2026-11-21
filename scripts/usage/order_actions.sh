#!/usr/bin/env bash
# READ ONLY: standard invocable actions for orders/contracts/assets/renewals
sf api request rest "/services/data/v$ORG_API/actions/standard" --target-org target 2>/dev/null | jq -r '.actions[] | select(.name|test("order|Order|contract|Contract|asset|Asset|renew|Renew|amend|Amend")) | "\(.name) | \(.label)"'
