#!/usr/bin/env bash
# Read-only: usage behind the invoice's account (Test usage 2) and where the line price came from.
set -uo pipefail
ACC="${ACC_ID:-001hm00000AiysLAAR}"; PROD=01thm000000tMcbAAE; UR=1BRhm0000001aW5GAI
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes) | with_entries(select(.value != null and (.key|test("^(IsDeleted|SystemModstamp|LastViewedDate|LastReferencedDate|LastModifiedById|CreatedById|OwnerId)$")|not)))] // .message' | head -c 4000; echo; }
echo "== assets"; q "SELECT Id, Name, Product2.ProductCode, Quantity, Price, CurrentAmount, LifecycleStartDate, LifecycleEndDate, Status FROM Asset WHERE AccountId='$ACC'"
echo "== transaction journals"; q "SELECT Id, Name, ReferenceRecordId, UsageResource.Name, Quantity, QuantityUnitOfMeasure.Name, Status, ActivityDate, StartDate, EndDate, CreatedDate FROM TransactionJournal WHERE AccountId='$ACC' ORDER BY CreatedDate"
echo "== usage summaries"; q "SELECT FIELDS(ALL) FROM UsageSummary WHERE Asset.AccountId='$ACC' LIMIT 20"
echo "== entitlement accounts"; q "SELECT FIELDS(ALL) FROM UsageEntitlementAccount WHERE AccountId='$ACC' LIMIT 10"
echo "== entitlement buckets"; q "SELECT Id, Name, UsageResource.Name, BucketBalance, TotalConsumedEntitlement, TotalAsOfBalance, TotalEntitlementAmount FROM UsageEntitlementBucket WHERE TransactionUsageEntitlement.AccountId='$ACC'"
echo "== ratable summaries"; q "SELECT FIELDS(ALL) FROM UsageRatableSummary WHERE AccountId='$ACC' LIMIT 20"
echo "== usage billing period items"; q "SELECT FIELDS(ALL) FROM UsageBillingPeriodItem WHERE AccountId='$ACC' LIMIT 20"
echo "== usage billing schedules"; q "SELECT Id, BillingScheduleNumber, ReferenceEntityId, UsageResourceId, Quantity, UnitPrice, TotalAmount, BillingMethod, Status, NextBillingDate FROM BillingSchedule WHERE BillingAccountId='$ACC'"
echo "== usage resource"; q "SELECT FIELDS(ALL) FROM UsageResource WHERE Id='$UR' LIMIT 1"
echo "== product usage resources"; q "SELECT FIELDS(ALL) FROM ProductUsageResource WHERE ProductId='$PROD' LIMIT 10"
echo "== product usage grants"; q "SELECT FIELDS(ALL) FROM ProductUsageGrant WHERE ProductUsageResource.ProductId='$PROD' LIMIT 10"
echo "== rate cards"; q "SELECT FIELDS(ALL) FROM RateCardEntry WHERE UsageResourceId='$UR' LIMIT 20"
echo "== rate adjustments"; q "SELECT FIELDS(ALL) FROM RateAdjustmentByTier WHERE RateCardEntry.UsageResourceId='$UR' LIMIT 20"
echo "== product + selling models"; q "SELECT Id, ProductCode, Name, Type, UsageModelType, (SELECT ProductSellingModel.Name, ProductSellingModel.SellingModelType, ProductSellingModel.PricingTerm, ProductSellingModel.PricingTermUnit FROM ProductSellingModelOptions) FROM Product2 WHERE Id='$PROD'"
echo "== price book entries"; q "SELECT Id, Pricebook2.Name, UnitPrice, CurrencyIsoCode, ProductSellingModel.Name, IsActive FROM PricebookEntry WHERE Product2Id='$PROD'"
echo "== quote line"; q "SELECT Id, Quote.Name, Quote.QuoteNumber, Quantity, ListPrice, UnitPrice, NetUnitPrice, TotalPrice, StartDate, EndDate, PeriodBoundary, BillingFrequency FROM QuoteLineItem WHERE Id='0QLhm0000009XBFGA2'"
echo "== orders"; q "SELECT Id, OrderNumber, Status, QuoteId, TotalAmount, CreatedDate FROM Order WHERE AccountId='$ACC' ORDER BY CreatedDate"
echo "== order items (all)"; q "SELECT Id, Order.OrderNumber, Product2.ProductCode, Quantity, ListPrice, UnitPrice, NetUnitPrice, TotalPrice, PricebookEntryId, QuoteLineItemId, ServiceDate, EndDate FROM OrderItem WHERE Order.AccountId='$ACC'"
echo "== failed batch records today"; q "SELECT BatchJobPart.Name, ErrorCode, ErrorMessage, RecordId, CreatedDate FROM BatchJobPartFailedRecord WHERE CreatedDate = LAST_N_DAYS:3 ORDER BY CreatedDate DESC LIMIT 8"
