#!/usr/bin/env bash
# READ ONLY: QuoteLinePriceAdjustment fields and the adjustments on the latest MR-103 test quotes
sf sobject describe --sobject QuoteLinePriceAdjustment --target-org target --json | jq -r '[.result.fields[] | "\(.name):\(.type)"] | join(" ")'
f=$(sf sobject describe --sobject QuoteLinePriceAdjustment --target-org target --json | jq -r '[.result.fields[] | select(.type!="address" and .type!="location" and (.name|test("^(Id|IsDeleted|CreatedById|LastModifiedById|SystemModstamp|CreatedDate|LastModifiedDate|LastViewedDate|LastReferencedDate|CurrencyIsoCode)$")|not)) | .name] | join(",")')
for qn in 00000224 00000225 00000226 00000232 00000231; do
  echo "== $qn line: $(sf data query --query "SELECT Product2.ProductCode, Quantity, ListPrice, UnitPrice, NetUnitPrice, Discount, TotalPrice, SubscriptionTerm, PricingTermCount FROM QuoteLineItem WHERE Quote.QuoteNumber = '$qn' AND Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT')" --target-org target --json | jq -c '.result.records[0] | del(.attributes) | .Product2 = .Product2.ProductCode')"
  sf data query --query "SELECT $f FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.Quote.QuoteNumber = '$qn' AND QuoteLineItem.Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT')" --target-org target --json | jq -c '.result.records[] | del(.attributes) | with_entries(select(.value != null))'
done
