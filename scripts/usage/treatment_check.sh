#!/usr/bin/env bash
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
echo "TREATMENTS $(q "SELECT Id, Name, Status, CanChangeBillingFrequency, BillingPolicyId, LegalEntityId, CurrencyIsoCode FROM BillingTreatment")"
echo "POLICIES $(q "SELECT Id, Name, Status, BillingTreatmentSelection, DefaultBillingTreatmentId FROM BillingPolicy")"
echo "ITEMS MB $(q "SELECT Name, Status, Type, BillingType, BillingTreatment.Name FROM BillingTreatmentItem WHERE BillingTreatment.Name LIKE 'Mindbody%'")"
echo "QB ANNUAL LINE $(q "SELECT Product2.ProductCode, Product2.BillingPolicy.Name, BillingFrequency, BillingTreatmentId, CreatedDate FROM QuoteLineItem WHERE BillingFrequency = 'Annual' ORDER BY CreatedDate DESC LIMIT 3")"
echo "ULT $(q "SELECT ProductCode, BillingPolicyId, TaxPolicyId, Allowed_Billing_Frequencies__c FROM Product2 WHERE ProductCode = 'MB-ULT'")"
