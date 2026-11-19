#!/usr/bin/env bash
# READ ONLY: bundle relationships (live and deleted) per quote.
set -uo pipefail
echo "== QuoteLineRelationship fields: $(sf sobject describe --sobject QuoteLineRelationship --target-org target --json | jq -c '[.result.fields[] | select(.custom == false) | .name]')"
for n in 00000110 00000146 00000156 00000160 00000161; do
  live=$(sf data query --query "SELECT Id, CreatedDate FROM QuoteLineRelationship WHERE MainQuoteLine.Quote.QuoteNumber = '$n'" --target-org target --json | jq -c '[.result.records[]? | .CreatedDate] | {count: length, created: (unique)}')
  dead=$(sf data query --all-rows --query "SELECT Id, CreatedDate, LastModifiedDate FROM QuoteLineRelationship WHERE IsDeleted = true AND MainQuoteLine.Quote.QuoteNumber = '$n'" --target-org target --json | jq -c '[.result.records[]? | .LastModifiedDate] | {count: length, deleted: (unique)}')
  echo "== $n live $live | deleted $dead"
done
echo "== deleted relationships today (any quote) by time"
sf data query --all-rows --query "SELECT LastModifiedDate, LastModifiedBy.Name FROM QuoteLineRelationship WHERE IsDeleted = true AND LastModifiedDate = TODAY ORDER BY LastModifiedDate" --target-org target --json | jq -c '[.result.records[]? | .LastModifiedDate] | group_by(.) | map({t: .[0], n: length})'
