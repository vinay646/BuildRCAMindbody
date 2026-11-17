#!/usr/bin/env bash
# Regression check of the 14 Nov tickets after the 16 Nov fixes. Data reads + an Apex probe whose inserts are ROLLED BACK (nothing saved).
set -uo pipefail
D=$(dirname "$0")
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== OPPORTUNITIES CREATED SINCE THE REGION RULE (16 Nov 15:36 UTC)"
raw "SELECT Name, Account.Region__c, Pricebook2.Name, CurrencyIsoCode, CreatedDate, CreatedBy.Name FROM Opportunity WHERE CreatedDate >= 2026-11-16T15:36:00Z ORDER BY CreatedDate"
echo "== QUOTE LINES CREATED SINCE THE 16 NOV FIXES"
raw "SELECT Quote.QuoteNumber, Product2.ProductCode, BillingFrequency, CreatedDate FROM QuoteLineItem WHERE CreatedDate >= 2026-11-16T11:00:00Z ORDER BY CreatedDate"
echo "== STARTER LINES BY BILLING FREQUENCY (all time)"
raw "SELECT BillingFrequency f, COUNT(Id) n FROM QuoteLineItem WHERE Product2.ProductCode = 'MB-STR' GROUP BY BillingFrequency"
echo "== ACCOUNTS FOR ENTERPRISE TESTS (Segment Enterprise + activated Master contract)"
raw "SELECT Account.Name, Account.Segment__c, Contract_Type__c, Status FROM Contract WHERE Contract_Type__c = 'Master'"
raw "SELECT Segment__c s, COUNT(Id) n FROM Account GROUP BY Segment__c"
echo "== APEX PROBE (rolled back)"
sf apex run --file "$D/apex/regression_rollback.apex" --target-org target --json > apex.json 2>&1
jq -r '.result.compiled, .result.success, (.result.compileProblem // ""), (.result.exceptionMessage // "")' apex.json
jq -r '.result.logs // ""' apex.json | grep -o 'RESULT.*' | sed 's/|DEBUG|//'
