#!/usr/bin/env bash
# READ ONLY: floor price pieces already in the org
echo "QLI floor fields: $(sf sobject describe --sobject QuoteLineItem --target-org target --json | jq -r '[.result.fields[] | select(.name|test("floor";"i")) | "\(.name):\(.type)"] | join(" ")')"
echo "floor flows: $(sf data query --query "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName LIKE '%Floor%'" --target-org target --json | jq -c '[.result.records[] | {ApiName, IsActive}]')"
echo "floor price books: $(sf data query --query "SELECT Id, Name, IsActive FROM Pricebook2 WHERE Name LIKE '%Floor%'" --target-org target --json | jq -c '[.result.records[] | {Id, Name, IsActive}]')"
echo "currencies: $(sf data query --query "SELECT IsoCode FROM CurrencyType WHERE IsActive = true" --target-org target --json | jq -r '[.result.records[].IsoCode] | join(",")')"
echo "standard entries for plans:"; sf data query --query "SELECT Product2.ProductCode, ProductSellingModel.Name, CurrencyIsoCode, UnitPrice FROM PricebookEntry WHERE Pricebook2.IsStandard = true AND Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT') AND IsActive = true ORDER BY Product2.ProductCode, CurrencyIsoCode" --target-org target 2>&1 | tail -30
echo "permission sets: $(sf data query --query "SELECT Name FROM PermissionSet WHERE Name IN ('Mindbody_ARM_Build','MB_Floor_Price')" --target-org target --json | jq -r '[.result.records[].Name] | join(",")')"
