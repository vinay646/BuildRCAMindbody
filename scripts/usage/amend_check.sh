#!/usr/bin/env bash
# READ ONLY: the amendment quote from the probe + asset renewal fields
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
q "SELECT QuoteNumber, OriginalActionType, OpportunityId, AccountId, Status, MB_MRR__c, StartDate, RLM_TermMonths__c FROM Quote WHERE Id = '0Q0hm0000007VK1CAM'" '.result.records[0] | del(.attributes)'
q "SELECT Product2.ProductCode, Quantity, NetUnitPrice, StartDate, EndDate FROM QuoteLineItem WHERE QuoteId = '0Q0hm0000007VK1CAM'" '[.result.records[] | {p: .Product2.ProductCode, qty: .Quantity, net: .NetUnitPrice, s: .StartDate, e: .EndDate}]'
sf sobject describe --sobject QuoteLineItem --target-org target --json | jq -c '[.result.fields[] | select(.name|test("ActionType|Delta|Amend|Renew";"i")) | .name]'
q "SELECT RenewalTerm, RenewalTermUnit, CurrentQuantity FROM Asset WHERE Id = '02ihm000000FuBZAA0'" '.result.records[0] | del(.attributes)'
sf sobject describe --sobject OrderItem --target-org target --json | jq -c '[.result.fields[] | select(.name|test("Renewal";"i")) | .name]'
q "SELECT Name, PricingTermUnit, RenewalTerm, RenewalTermUnit FROM ProductSellingModel WHERE Name = 'Term Monthly'" '.result.records[0] | del(.attributes)' 2>/dev/null
