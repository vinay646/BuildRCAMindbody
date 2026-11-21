#!/usr/bin/env bash
# CHANGES test data (MR103 Q2C04 account): 5% uplift on its first Ultimate asset, renew it, show the renewal quote prices; amended asset quantity
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
acc=$(q "SELECT Id FROM Account WHERE Name LIKE 'MR103 Q2C04%' LIMIT 1" '.result.records[0].Id' | tr -d '"')
a=$(q "SELECT Id FROM Asset WHERE AccountId = '$acc' AND Name = 'Ultimate' ORDER BY CreatedDate LIMIT 1" '.result.records[0].Id' | tr -d '"')
echo "amended asset periods: $(q "SELECT StartDate, EndDate, Quantity, Amount FROM AssetStatePeriod WHERE AssetId = '$a' ORDER BY StartDate" '[.result.records[] | del(.attributes)]')"
sf data update record --sobject Asset --record-id $a --values "UnitPriceUplift=5 RenewalTerm=12 RenewalTermUnit=Months" --target-org target --json | jq -c '{uplift: .status, message}'
r=$(sf api request rest "$API/actions/standard/initiateRenewal" --method POST --body "{\"inputs\":[{\"renewAssetIds\":[\"$a\"],\"renewOutputType\":\"Quote\"}]}" --target-org target 2>&1 | jq -r '.[0].outputValues.renewRecordId // .[0].errors[0].message')
echo "renewal quote: $r"; sleep 40
echo "renewal lines: $(q "SELECT Product2.ProductCode, Quantity, ListPrice, UnitPrice, NetUnitPrice, UnitPriceUplift, ApplUnitPriceUpliftPct, StartDate, EndDate FROM QuoteLineItem WHERE QuoteId = '$r' AND Product2.ProductCode = 'MB-ULT'" '[.result.records[] | del(.attributes, .Product2)]')"
echo "renewal quote: $(q "SELECT QuoteNumber, OpportunityId, Opportunity.Type, MB_MRR__c FROM Quote WHERE Id = '$r'" '.result.records[0] | {QuoteNumber, type: .Opportunity.Type, MB_MRR__c}')"
