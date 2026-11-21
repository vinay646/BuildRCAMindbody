#!/usr/bin/env bash
# READ ONLY: why an order (ON env, default 00000115) is not activated
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
n=${ON:-00000115}
q "SELECT Id, Status, QuoteId, Quote.QuoteNumber, ContractId, MB_Activation_Error__c, BillToContactId, BillingStreet, ShippingStreet, EffectiveDate, AccountId, Account.Name, Account.BillingStreet, Account.ShippingStreet, CreatedDate, CreatedBy.Name FROM Order WHERE OrderNumber = '$n'" '.result.records[0] | del(.attributes)'
id=$(q "SELECT Id FROM Order WHERE OrderNumber = '$n'" '.result.records[0].Id' | tr -d '"')
echo "tasks: $(q "SELECT Subject, Description FROM Task WHERE WhatId = '$id'" '[.result.records[] | {Subject, Description}]')"
echo "contacts on account: $(q "SELECT COUNT() FROM Contact WHERE AccountId IN (SELECT AccountId FROM Order WHERE Id = '$id')" .result.totalSize)"
echo "flow errors: $(q "SELECT FlowVersionView.FlowDefinitionView.ApiName, InterviewLabel, CurrentElement, InterviewStatus, CreatedDate FROM FlowInterview WHERE CreatedDate = TODAY AND InterviewLabel LIKE 'MB Order%' ORDER BY CreatedDate DESC LIMIT 5" '[.result.records[]? | del(.attributes)]' 2>/dev/null)"
