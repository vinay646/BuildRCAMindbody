#!/usr/bin/env bash
# READ-ONLY QA for MB-ATT-03 Regional price books.
set -uo pipefail
raw() { sf data query --query "$1" --target-org target --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
echo "== PRICE BOOKS"; raw "SELECT Id, Name, IsActive, IsStandard, Description FROM Pricebook2"
echo "== ENTRIES"; raw "SELECT Pricebook2.Name, Product2.ProductCode, CurrencyIsoCode, ProductSellingModel.Name, UnitPrice, IsActive FROM PricebookEntry WHERE Product2.ProductCode LIKE 'MB-%'"
