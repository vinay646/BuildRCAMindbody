#!/usr/bin/env bash
# Read-only: why rating failed - failed ratable summary (non-null fields), a rated one for comparison, asset rate card entries old vs new
nn() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes) | with_entries(select(.value != null and .value != false and .value != 0 and (.key|test("Created|LastModified|System|Owner|Viewed|Referenced")|not)))]'; }
echo "FAILED $(nn "SELECT FIELDS(ALL) FROM UsageRatableSummary WHERE Status = 'RatingFailed' AND Account.Name LIKE 'MBUsage-%' ORDER BY CreatedDate DESC LIMIT 1")"
echo "RATED $(nn "SELECT FIELDS(ALL) FROM UsageRatableSummary WHERE TotalAmount > 0 ORDER BY CreatedDate DESC LIMIT 1")"
echo "OLD ASSET RCE $(nn "SELECT FIELDS(ALL) FROM AssetRateCardEntry WHERE AssetId = '02ihm000000EpYvAAK' LIMIT 2")"
echo "OLD QLRCE $(sf data query --query "SELECT COUNT() FROM QuoteLineRateCardEntry" --target-org target --json | jq -c .result.totalSize)"
