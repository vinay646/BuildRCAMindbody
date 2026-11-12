#!/usr/bin/env bash
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
for QID in $(q "SELECT Id FROM Quote WHERE Account.Name = 'Pulse Fitness Brands' ORDER BY LastModifiedDate DESC LIMIT 2" | jq -r '.[].Id'); do
  echo "QUOTE $(q "SELECT QuoteNumber, Name, StartDate, RLM_TermMonths__c, RLM_EndDate__c, Hierarchy_Location_Count__c, LegalEntity.Name, CalculationStatus, CreatedDate, LastModifiedDate FROM Quote WHERE Id = '$QID'")"
  echo "LINES $(q "SELECT Product2.ProductCode, Quantity, BillingFrequency, SubscriptionTerm, SubscriptionTermUnit, StartDate, EndDate, ListPrice, NetUnitPrice, BillingTreatment.Name, CreatedDate FROM QuoteLineItem WHERE QuoteId = '$QID'")"
done
