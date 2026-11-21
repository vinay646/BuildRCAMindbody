#!/usr/bin/env bash
# READ ONLY: billing setup and state for MR-111
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
oid=$(q "SELECT Id FROM Order WHERE OrderNumber = '00000118'" '.result.records[0].Id' | tr -d '"')
echo "schedules (order 118): $(q "SELECT ReferenceEntityItem.Name, Status, BillingTermUnit, BillingMethod, BillingScheduleStartDate, BillingScheduleEndDate, NextBillingDate, TotalAmount, CurrencyIsoCode, BillingTreatment.Name FROM BillingSchedule WHERE ReferenceEntityId = '$oid'" '[.result.records[] | del(.attributes) | .ReferenceEntityItem = .ReferenceEntityItem.Name | .BillingTreatment = .BillingTreatment.Name]' 2>&1 | head -c 1500)"
echo "billing treatments: $(q "SELECT Name, BillingPolicy.Name, LegalEntity.Name, Status FROM BillingTreatment" '[.result.records[] | "\(.Name)|\(.BillingPolicy.Name)|\(.LegalEntity.Name)|\(.Status)"]' 2>&1 | head -c 800)"
echo "treatment items: $(q "SELECT Name, BillingType, BillingTreatment.Name, ProcessingOrder FROM BillingTreatmentItem" '[.result.records[] | "\(.BillingTreatment.Name)|\(.BillingType)|\(.Name)"]' 2>&1 | head -c 800)"
echo "tax policies: $(q "SELECT Name, Status, DefaultTaxTreatment.Name FROM TaxPolicy" '[.result.records[] | del(.attributes)]' 2>&1 | head -c 500)"
echo "tax treatments: $(q "SELECT Name, Status, TaxEngine.TaxEngineName, LegalEntity.Name, TaxCode FROM TaxTreatment" '[.result.records[] | del(.attributes)]' 2>&1 | head -c 800)"
echo "tax engines: $(q "SELECT TaxEngineName, Status, MerchantCredentialId FROM TaxEngine" '[.result.records[] | del(.attributes)]' 2>&1 | head -c 400)"
echo "invoices: $(q "SELECT Status, COUNT(Id) n FROM Invoice GROUP BY Status" '[.result.records[] | "\(.Status):\(.n)"]' 2>&1 | head -c 300)"
echo "invoice runs: $(q "SELECT Status, COUNT(Id) n FROM BillingBatchScheduler GROUP BY Status" '[.result.records[] | "\(.Status):\(.n)"]' 2>&1 | head -c 300)"
sf api request rest "/services/data/v$ORG_API/actions/standard" --target-org target 2>/dev/null | jq -r '.actions[] | select(.name|test("nvoice|illing|Tax|tax")) | .name' | tr '\n' ' '; echo
