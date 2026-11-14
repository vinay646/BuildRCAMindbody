#!/usr/bin/env bash
# READ-ONLY QA for MB-PRD-02 Enterprise.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes) | with_entries(select(.value != null and (.key|test("^(IsDeleted|SystemModstamp|LastViewedDate|LastReferencedDate|LastModifiedById|CreatedById|OwnerId|CreatedDate|LastModifiedDate)$")|not)))] else {error: .message} end'; }
echo "== PRODUCT"; raw "SELECT ProductCode, Name, IsActive, Type, ConfigureDuringSale, QuantityUnitOfMeasure FROM Product2 WHERE ProductCode = 'MB-ENT'"
echo "== SELLING MODELS"; raw "SELECT ProductSellingModel.Name FROM ProductSellingModelOption WHERE Product2.ProductCode = 'MB-ENT'"
echo "== PRICES"; raw "SELECT Pricebook2.Name, CurrencyIsoCode, UnitPrice, ProductSellingModel.Name, IsActive FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ENT' ORDER BY Pricebook2.Name, CurrencyIsoCode"
echo "== MASTER CONTRACT LOOKUPS"; for o in Account Contract Quote; do echo "$o $(sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Master";"i")) | {name, type, referenceTo}]')"; done
