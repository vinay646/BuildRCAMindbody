#!/usr/bin/env bash
# READ ONLY: is there a standard billing frequency field on Quote; QLI picklist values; what flows already touch it.
set -uo pipefail
for o in Quote QuoteLineItem; do
  echo "== $o fields with billing / frequency"
  sf sobject describe --sobject $o --target-org target --json | jq -r '.result.fields[] | select(.name|test("(?i)billing|freq")) | "  \(.name) | \(.type) | custom=\(.custom) | updateable=\(.updateable) | \([.picklistValues[]?.value]|join(","))"'
done
echo "== GlobalValueSet / StandardValueSet usage check: OrderItem BillingFrequency2"
sf sobject describe --sobject OrderItem --target-org target --json | jq -r '.result.fields[] | select(.name|test("(?i)billingfreq")) | "  \(.name) | \([.picklistValues[]?.value]|join(","))"'
echo "== Active record-triggered flows on Quote / QuoteLineItem"
sf data query --use-tooling-api --query "SELECT ApiName, TriggerObjectOrEventLabel, TriggerType, RecordTriggerType FROM FlowDefinitionView WHERE IsActive = true AND TriggerObjectOrEventLabel IN ('Quote','Quote Line Item')" --target-org target --json 2>/dev/null | jq -r '.result.records[]? | "  \(.ApiName) | \(.TriggerObjectOrEventLabel) | \(.TriggerType) | \(.RecordTriggerType)"'
echo "== Recent quote line frequencies"
sf data query --query "SELECT BillingFrequency f, COUNT(Id) n FROM QuoteLineItem GROUP BY BillingFrequency" --target-org target --json | jq -c '.result.records'
