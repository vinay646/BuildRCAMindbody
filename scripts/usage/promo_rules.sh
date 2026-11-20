#!/usr/bin/env bash
# READ ONLY: rule-library related objects and their records
sf sobject list --target-org target 2>/dev/null | grep -i -E '^(Rule|BusinessRule|Promotion|Coupon|Decision)' | tr '\n' ' '; echo
for o in $(sf sobject list --target-org target 2>/dev/null | grep -i -E '^(Rule[A-Za-z]*|PromotionSegment[A-Za-z]*|BusinessRule[A-Za-z]*)$'); do
  echo "== $o"; sf data query --query "SELECT FIELDS(STANDARD) FROM $o ORDER BY CreatedDate DESC LIMIT 8" --target-org target --json 2>/dev/null | jq -c '.result.records[]? | del(.attributes,.OwnerId,.CreatedById,.LastModifiedById,.SystemModstamp,.IsDeleted,.LastViewedDate,.LastReferencedDate,.CurrencyIsoCode)' | cut -c1-400
done
