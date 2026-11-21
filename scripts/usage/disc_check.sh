#!/usr/bin/env bash
# READ ONLY: where do rep discounts live? lines with Discount, DiscountAmount or Discretionary adjustments
sf data query --query "SELECT Quote.QuoteNumber, Product2.ProductCode, ListPrice, NetUnitPrice, Discount, DiscountAmount, CreatedBy.Name FROM QuoteLineItem WHERE Discount > 0 OR DiscountAmount > 0 ORDER BY LastModifiedDate DESC LIMIT 8" --target-org target 2>&1 | tail -11
sf data query --query "SELECT QuoteLineItem.Quote.QuoteNumber, AdjustmentSource, AdjustmentType, AdjustmentValue, AppliedAdjustmentAmount, CreatedBy.Name FROM QuoteLinePriceAdjustment WHERE AdjustmentSource IN ('Discretionary','System') ORDER BY CreatedDate DESC LIMIT 6" --target-org target 2>&1 | tail -9
