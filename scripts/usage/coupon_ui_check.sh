#!/usr/bin/env bash
# READ ONLY: recent quotes with a Coupon Code (UI tests), their coupon adjustments, and whether the async reprice ran / failed.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
qt() { sf data query --use-tooling-api --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
echo "== quotes with a coupon, last 2 days (not created by the test scripts)"
q "SELECT Id, QuoteNumber, Name, Coupon_Code__c, LastModifiedDate, LastModifiedBy.Name, CreatedBy.Name, CalculationStatus FROM Quote WHERE LastModifiedDate = LAST_N_DAYS:2 AND (NOT Name LIKE 'COUPON%') AND (NOT Name LIKE 'BILLFREQ%') ORDER BY LastModifiedDate DESC LIMIT 8" | jq -c '.[]'
for id in $(q "SELECT Id FROM Quote WHERE LastModifiedDate = LAST_N_DAYS:2 AND (NOT Name LIKE 'COUPON%') AND (NOT Name LIKE 'BILLFREQ%') ORDER BY LastModifiedDate DESC LIMIT 4" | jq -r '.[].Id'); do
  echo "-- quote $id lines"
  q "SELECT Id, Product2.ProductCode, ProductSellingModel.Name, ListPrice, NetUnitPrice, LastModifiedDate, CreatedDate FROM QuoteLineItem WHERE QuoteId = '$id'" | jq -c '.[]'
  echo "   adjustments"
  q "SELECT QuoteLineItem.Product2.ProductCode, AdjustmentSource, AdjustmentValue, CouponCode, PriceAdjustmentCauseId, Description, CreatedDate, CreatedBy.Name FROM QuoteLinePriceAdjustment WHERE QuoteLineItem.QuoteId = '$id' ORDER BY CreatedDate" | jq -c '.[]'
  echo "   history"
  q "SELECT Field, OldValue, NewValue, CreatedDate, CreatedBy.Name FROM QuoteHistory WHERE QuoteId = '$id' ORDER BY CreatedDate DESC LIMIT 10" | jq -c '.[]?' 2>/dev/null
done
echo "== flow interviews (paused / failed)"
q "SELECT Id, Name, InterviewLabel, InterviewStatus, CurrentElement, CreatedDate, CreatedBy.Name FROM FlowInterview WHERE CreatedDate = LAST_N_DAYS:2 ORDER BY CreatedDate DESC LIMIT 15" | jq -c '.[]?'
echo "== flow interview logs"
q "SELECT FlowDeveloperName, InterviewStatus, InterviewStartTimestamp, InterviewEndTimestamp, CreatedBy.Name FROM FlowInterviewLog WHERE FlowDeveloperName LIKE 'MB_Quote%Coupon%' ORDER BY CreatedDate DESC LIMIT 15" | jq -c '.[]?'
echo "== async apex / flow jobs today"
q "SELECT JobType, ApexClass.Name, Status, NumberOfErrors, ExtendedStatus, CreatedDate, CreatedBy.Name FROM AsyncApexJob WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 15" | jq -c '.[]?'
echo "== users who touched quotes today"
q "SELECT LastModifiedBy.Name n, LastModifiedBy.Username u, COUNT(Id) c FROM Quote WHERE LastModifiedDate = TODAY GROUP BY LastModifiedBy.Name, LastModifiedBy.Username"
echo "== debug logs for RepriceQuotesPST / flows today"
qt "SELECT Id, Operation, Status, Request, StartTime, LogUser.Name FROM ApexLog WHERE StartTime = TODAY ORDER BY StartTime DESC LIMIT 10"
