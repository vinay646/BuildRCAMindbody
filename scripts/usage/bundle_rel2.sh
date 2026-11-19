#!/usr/bin/env bash
# READ ONLY: relationship detail (pre-coupon quote 00000110 vs coupon quote 00000161) and the Accelerate bundle's group rules.
set -uo pipefail
for n in 00000110 00000161; do
  echo "== $n"
  sf data query --query "SELECT AssociatedQuoteLine.Product2.ProductCode, MainQuoteLineRole, AssociatedQuoteLineRole, AssociatedQuoteLinePricing, ProductRelationshipTypeId, ProductRelatedComponentId, ProductRelatedComponent.ProductComponentGroup.Name, RootQuoteLineId FROM QuoteLineRelationship WHERE MainQuoteLine.Quote.QuoteNumber = '$n' ORDER BY AssociatedQuoteLine.Product2.ProductCode" --target-org target --json | jq -c '.result.records[]? | {p: .AssociatedQuoteLine.Product2.ProductCode, roles: [.MainQuoteLineRole, .AssociatedQuoteLineRole], pricing: .AssociatedQuoteLinePricing, prc: .ProductRelatedComponentId, group: .ProductRelatedComponent.ProductComponentGroup.Name, root: (.RootQuoteLineId != null)}'
done
echo "== Accelerate component groups"
sf data query --query "SELECT Name, MinBundleComponents, MaxBundleComponents, ParentGroup.Name, Sequence FROM ProductComponentGroup WHERE ParentProduct.ProductCode = 'MB-ACC' ORDER BY Sequence" --target-org target --json | jq -c '.result.records[]? | del(.attributes)'
echo "== Accelerate related components"
sf data query --query "SELECT ChildProduct.ProductCode, ProductComponentGroup.Name, IsComponentRequired, IsDefaultComponent, Quantity, MinQuantity FROM ProductRelatedComponent WHERE ParentProduct.ProductCode = 'MB-ACC'" --target-org target --json | jq -c '.result.records[]? | del(.attributes)'
