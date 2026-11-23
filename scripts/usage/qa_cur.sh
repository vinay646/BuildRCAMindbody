#!/usr/bin/env bash
# Read-only: frequency and term tiers by currency, and priced plan lines by currency in QA
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
for N in "Mind-Body Billing Frequency Discount schedule" "Contract Term Discount" "Mind-Body Volume Discount by Hierarchy Locations"; do
  S=$(q "SELECT Id FROM PriceAdjustmentSchedule WHERE Name = '$N'" | jq -r '.[0].Id'); echo "== $N"
  q "SELECT Product2.ProductCode, CurrencyIsoCode, LowerBound, UpperBound, TierValue, ProductSellingModel.Name FROM PriceAdjustmentTier WHERE PriceAdjustmentScheduleId = '$S' ORDER BY Product2.ProductCode, CurrencyIsoCode, LowerBound" | jq -r 'group_by(.Product2.ProductCode + " " + .CurrencyIsoCode)[] | "\(.[0].Product2.ProductCode) \(.[0].CurrencyIsoCode): " + ([.[] | "\(.LowerBound)-\(.UpperBound)=\(.TierValue)%(\(.ProductSellingModel.Name // "-"))"] | join(", "))'
done
echo "== PRICED LINES"
q "SELECT CurrencyIsoCode, Quote.QuoteNumber, Quote.Account.Name, Quote.Location_count__c, Quote.RLM_TermMonths__c, Product2.ProductCode, Quantity, BillingFrequency, ListPrice, NetUnitPrice FROM QuoteLineItem WHERE Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT') AND NetUnitPrice != null AND CurrencyIsoCode != 'USD' ORDER BY CurrencyIsoCode, CreatedDate DESC LIMIT 30" | jq -r '.[] | [.CurrencyIsoCode, .Quote.QuoteNumber, .Quote.Account.Name, "loc", .Quote.Location_count__c, "term", .Quote.RLM_TermMonths__c, .Product2.ProductCode, "qty", .Quantity, .BillingFrequency, .ListPrice, .NetUnitPrice] | @tsv'
