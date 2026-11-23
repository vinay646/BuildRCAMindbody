#!/usr/bin/env bash
# Read-only: what of the quoting and approval build exists in the target org (flows, fields, groups, promotions, pricing, document)
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
t() { sf data query --use-tooling-api --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
echo "FLOWS $(q "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName LIKE 'MB_%' OR ApiName LIKE 'RLM_Quote%'" | jq -c '[.[] | (.ApiName + (if .IsActive then "" else "(off)" end))]')"
echo "QLI FIELDS $(t "SELECT DeveloperName FROM CustomField WHERE TableEnumOrId = 'QuoteLineItem' AND DeveloperName LIKE 'MB_%'" | jq -c '[.[].DeveloperName]')"
echo "QUOTE FIELDS $(t "SELECT DeveloperName FROM CustomField WHERE TableEnumOrId = 'Quote' AND (DeveloperName LIKE 'MB_%' OR DeveloperName LIKE 'Coupon%' OR DeveloperName LIKE '%Location%')" | jq -c '[.[].DeveloperName]')"
echo "GROUPS $(q "SELECT DeveloperName FROM Group WHERE DeveloperName LIKE 'MB_%'" | jq -c '[.[].DeveloperName]')"
echo "PROMOS $(q "SELECT Name, IsActive FROM Promotion" | jq -c '[.[] | .Name]')"
echo "PRICING ACTIVE $(q "SELECT ExpressionSetDefinition.DeveloperName, VersionNumber FROM ExpressionSetVersion WHERE IsActive = true AND ExpressionSetDefinition.DeveloperName LIKE '%Pricing%'")"
echo "TIER CURRENCIES $(q "SELECT CurrencyIsoCode c, COUNT(Id) n FROM PriceAdjustmentTier GROUP BY CurrencyIsoCode")"
echo "QUOTE DOC $(t "SELECT DeveloperName FROM FlexiPage WHERE DeveloperName LIKE '%Mindbody_Quote%'" | jq -c '[.[].DeveloperName]')"
echo "VALIDATION $(t "SELECT ValidationName, Active FROM ValidationRule WHERE ValidationName LIKE 'MB_%'" | jq -c '[.[] | .ValidationName]')"
echo "QUOTE STATUS VOIDED $(sf sobject describe --sobject Quote --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.name=="Status") | .picklistValues[].value]')"
echo "CLASSES $(t "SELECT Name FROM ApexClass WHERE Name IN ('MbCouponRules','RepriceQuotesPST','AccountHierarchyService')" | jq -c '[.[].Name]')"
