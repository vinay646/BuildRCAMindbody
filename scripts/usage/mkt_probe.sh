#!/usr/bin/env bash
# Read-only: Marketplace usage set-up and Transaction Journal fields
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
echo "RES $(q "SELECT Id, Name, Code, Status, UnitOfMeasureClassId, UnitOfMeasureClass.Name, DefaultUnitOfMeasure.Name, DefaultUnitOfMeasure.UnitCode FROM UsageResource WHERE Code LIKE '%MKT%'")"
echo "UOMS $(q "SELECT Id, Name, UnitCode, Status, UnitOfMeasureClass.Name FROM UnitOfMeasure WHERE UnitOfMeasureClass.Name IN ('First Purchase','Fee Amount') OR Name LIKE '%Purchase%' OR Name LIKE '%Fee%'")"
echo "UOMCLASS $(q "SELECT Id, Name, Code, Type, Status FROM UnitOfMeasureClass")"
echo "PUR $(q "SELECT Id, Product.ProductCode, UsageResource.Code, Status FROM ProductUsageResource WHERE Product.ProductCode = 'MB-MKT'")"
echo "RCE $(q "SELECT Id, RateCard.Name, RateCardType, UsageResource.Code, Rate, Status, DefaultUnitOfMeasure.Name FROM RateCardEntry WHERE Product.ProductCode = 'MB-MKT'")"
echo "TJFIELDS $(sf sobject describe --sobject TransactionJournal --target-org target --json | jq -c '[.result.fields[] | select(.custom or (.name|test("Quantity|Amount|UsageResource|Unit|Reference|Activity"))) | [.name,.type,.createable]]')"
echo "TJTRIG $(sf sobject describe --sobject TransactionJournal --target-org target --json | jq -c '.result | {triggerable, createable, customSetting}')"
