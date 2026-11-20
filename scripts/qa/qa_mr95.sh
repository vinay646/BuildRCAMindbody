#!/usr/bin/env bash
# READ-ONLY: where is the Enterprise master-contract check now (MR-95)?
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== qualification / disqualification rows on MB-ENT"
raw "SELECT FIELDS(STANDARD) FROM ProductQualification WHERE Product.ProductCode = 'MB-ENT'"
raw "SELECT FIELDS(STANDARD) FROM ProductDisqualification WHERE Product.ProductCode = 'MB-ENT'"
echo "== flow versions of Validation_QLE_Check_Master_Contract_for_Enterprise_Products"
raw "SELECT VersionNumber, Status, LastModifiedDate, LastModifiedBy.Name, Description FROM Flow WHERE Definition.DeveloperName = 'Validation_QLE_Check_Master_Contract_for_Enterprise_Products' ORDER BY VersionNumber" "--use-tooling-api"
echo "== every active flow mentioning Master in its metadata"
for id in $(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Status = 'Active' AND ProcessType = 'AutoLaunchedFlow'" --target-org target --json | jq -r '.result.records[].Id'); do
  m=$(sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target 2>/dev/null)
  if echo "$m" | grep -q -i "Master"; then echo "   $(echo "$m" | jq -r '.FullName // .MasterLabel') : $(echo "$m" | jq -c '.Metadata.start | {o: .object, t: .recordTriggerType}')"; fi
done
echo "== CML models mentioning master/contract"
for id in $(sf data query --use-tooling-api --query "SELECT Id FROM ExpressionSetDefinitionVersion WHERE DeveloperName LIKE '%Mindbody%' OR DeveloperName LIKE '%MB%'" --target-org target --json | jq -r '.result.records[].Id'); do echo "   $id"; done
echo "== Enterprise quote lines added since 19 Nov 17:08 and their accounts' master contracts"
raw "SELECT Quote.QuoteNumber, Quote.Opportunity.Account.Name, Quote.Opportunity.Account.Segment__c, CreatedDate, CreatedBy.Name FROM QuoteLineItem WHERE Product2.ProductCode = 'MB-ENT' AND CreatedDate >= 2026-11-19T17:08:00Z"
raw "SELECT Account.Name, Contract_Type__c, Status FROM Contract WHERE Contract_Type__c = 'Master'"
