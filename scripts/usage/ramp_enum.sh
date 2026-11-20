#!/usr/bin/env bash
# Probe: allowed groupRampAction values (invalid value on test quote 00000218, no change expected)
API="/services/data/v$ORG_API"; Q=0Q0hm000000782TCAQ
B='{"groupRampAction":"Xyz","pricingPref":"System","graph":{"graphId":"g","records":[{"referenceId":"'$Q'","record":{"attributes":{"type":"Quote","method":"PATCH","id":"'$Q'"}}}]}}'
sf api request rest "$API/connect/rev/sales-transaction/actions/place" --method POST --body "$B" --target-org target 2>&1 | head -c 1500; echo
B2='{"recordIds":["1C9hm000000HgcLCAS"],"salesTransactionId":"'$Q'","options":{"lineScope":"Xyz"}}'
sf api request rest "$API/connect/rev/sales-transaction/actions/clone" --method POST --body "$B2" --target-org target 2>&1 | head -c 1500; echo
sf data query --query "SELECT Id, Product2.ProductCode, QuoteLineGroupId, RampIdentifier, SegmentIdentifier, IsPrimarySegment, SellingModelType, PeriodBoundary FROM QuoteLineItem WHERE QuoteId='$Q'" --target-org target 2>&1 | tail -6
