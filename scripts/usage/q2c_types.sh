#!/usr/bin/env bash
# READ ONLY: field types needed for MR-118
sf sobject describe --sobject Opportunity --target-org target --json | jq -c '[.result.fields[] | select(.name|test("MB_Legal_Entity__c|MB_Hierarchy_Location_Count__c|SyncedQuoteId")) | {name, type, updateable, calculated}]'
sf sobject describe --sobject Quote --target-org target --json | jq -c '[.result.fields[] | select(.name|test("^(LegalEntityId|StartDate|RLM_EndDate__c|RLM_TermMonths__c|Hierarchy_Location_Count__c|MB_Billing_Frequency__c|Status|IsSyncing)$")) | {name, type, calculated}]'
sf sobject describe --sobject QuoteLineItem --target-org target --json | jq -c '[.result.fields[] | select(.name|test("^(SellingModelType|NetTotalPrice|TotalPrice|LegalEntityId)$")) | {name, type, picklist: [.picklistValues[]?.value]}]'
