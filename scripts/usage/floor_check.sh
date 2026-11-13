#!/usr/bin/env bash
# Floor price book Id and entries (PRC-18), new quote line floor fields, and the context attribute.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
echo "FLOOR BOOK $(q "SELECT Id, Name, IsActive FROM Pricebook2 WHERE Name = 'Mindbody Floor Prices'")"
echo "FLOOR ENTRIES $(q "SELECT Product2.ProductCode, CurrencyIsoCode, UnitPrice, ProductSellingModel.Name, IsActive FROM PricebookEntry WHERE Pricebook2.Name = 'Mindbody Floor Prices' ORDER BY Product2.ProductCode, CurrencyIsoCode" | jq -c '[.[] | "\(.Product2.ProductCode) \(.CurrencyIsoCode) \(.UnitPrice) \(.ProductSellingModel.Name) \(.IsActive)"]')"
echo "QLI FIELDS $(sf api request rest "$API/sobjects/QuoteLineItem/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Floor")) | {name, type, calculated}]')"
echo "PBE DECISION TABLE $(q "SELECT Id, DeveloperName, Status, SourceObject FROM DecisionTable WHERE DeveloperName = 'Price_Book_Entry_Decision_Table_v2'")"
