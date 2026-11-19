#!/usr/bin/env bash
# READ ONLY: lines and bundle relationships of the quotes under opportunities named COUPON-FLOW 1119-1155, with creation times.
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
for row in $(q "SELECT Id, QuoteNumber, CreatedDate FROM Quote WHERE Opportunity.Name = 'COUPON-FLOW 1119-1155' ORDER BY CreatedDate" | jq -r '.[] | "\(.Id)|\(.QuoteNumber)|\(.CreatedDate)"'); do
  IFS='|' read -r id n c <<< "$row"
  echo "== quote $n created $c"
  q "SELECT Product2.ProductCode, Product2.Name, NetUnitPrice, CreatedDate FROM QuoteLineItem WHERE QuoteId = '$id' ORDER BY CreatedDate" | jq -c '.[] | {p: .Product2.ProductCode, n: .Product2.Name, net: .NetUnitPrice, t: .CreatedDate}'
  echo "   relationships: $(q "SELECT COUNT() FROM QuoteLineRelationship WHERE MainQuoteLine.QuoteId = '$id'" 2>/dev/null | head -c 200)"
done
echo "== UI-built Accelerate bundle for comparison (quote 00000146)"
q "SELECT Product2.ProductCode, Product2.Name FROM QuoteLineItem WHERE Quote.QuoteNumber = '00000146' ORDER BY Product2.ProductCode" | jq -c '[.[] | .Product2.Name]'
