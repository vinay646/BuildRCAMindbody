#!/usr/bin/env bash
# Probes the standard ramp deal endpoints with a test quote (00000213, "MR103 ramp probe"). May CREATE a ramp on that quote.
API="/services/data/v$ORG_API"
Q=0Q0hm00000077eHCAQ; L=0QLhm000000AdZZGA0
for ep in ramp-deal-create ramp-deal/create create-ramp-deal; do
  echo "== $ep {}"; sf api request rest "$API/connect/rev/sales-transaction/actions/$ep" --method POST --body '{}' --target-org target 2>&1 | head -c 600; echo
done
B1='{"transactionId":"'$Q'","transactionLineId":"'$L'","subscriptionTerm":12,"subscriptionTermUnit":"Months","segments":[{"segmentType":"Custom","startDate":"2026-11-20","endDate":"2027-02-19","segmentName":"Months 1-3"},{"segmentType":"Custom","startDate":"2027-02-20","endDate":"2027-11-19","segmentName":"Months 4-12"}]}'
echo "== create B1"; sf api request rest "$API/connect/rev/sales-transaction/actions/ramp-deal-create" --method POST --body "$B1" --target-org target 2>&1 | head -c 1500; echo
sleep 15
sf data query --query "SELECT Id, Name, Type, IsRamped, SegmentType, StartDate, EndDate FROM QuoteLineGroup WHERE QuoteId='$Q'" --target-org target 2>&1 | tail -8
sf data query --query "SELECT Product2.ProductCode, QuoteLineGroupId, StartDate, EndDate, SegmentIdentifier, SegmentType, IsPrimarySegment FROM QuoteLineItem WHERE QuoteId='$Q'" --target-org target 2>&1 | tail -8
