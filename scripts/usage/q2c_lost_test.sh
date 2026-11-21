#!/usr/bin/env bash
# CHANGES test data: MR-118 1.5 (product on a synced opportunity blocked) and MR-122 4.13 (renewal lost) on MR103 test records
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
O=$(q "SELECT Id, Pricebook2Id FROM Opportunity WHERE SyncedQuoteId != null AND IsClosed = false AND Name LIKE 'MR103%' ORDER BY CreatedDate DESC LIMIT 1" '.result.records[0]')
opp=$(echo $O | jq -r .Id); pb=$(echo $O | jq -r .Pricebook2Id)
pbe=$(q "SELECT Id FROM PricebookEntry WHERE Pricebook2Id = '$pb' AND Product2.ProductCode = 'MB-TAM' AND CurrencyIsoCode = 'USD' AND IsActive = true LIMIT 1" '.result.records[0].Id' | tr -d '"')
r=$(sf data create record --sobject OpportunityLineItem --values "OpportunityId=$opp PricebookEntryId=$pbe Quantity=1 UnitPrice=100" --target-org target --json | jq -c '{status, message}')
echo "T5 $(echo $r | jq -r 'if .status != 0 then "PASS" else "FAIL" end') | $(echo $r | jq -r .message | head -c 160)"
acc=$(q "SELECT Id FROM Account WHERE Name LIKE 'MR103 Q2C04 1%' ORDER BY CreatedDate LIMIT 1" '.result.records[0].Id' | tr -d '"')
ren=$(q "SELECT Id FROM Opportunity WHERE AccountId = '$acc' AND Type = 'Renewal' AND IsClosed = false LIMIT 1" '.result.records[0].Id' | tr -d '"')
echo "before: contracts not renewing $(q "SELECT COUNT() FROM Contract WHERE AccountId = '$acc' AND MB_Do_Not_Renew__c = true" .result.totalSize), assets auto-renew $(q "SELECT COUNT() FROM Asset WHERE AccountId = '$acc' AND DoesAutomaticallyRenew = true" .result.totalSize)"
sf data update record --sobject Opportunity --record-id $ren --values "StageName='Closed Lost'" --target-org target --json | jq -c '{lost: .status, message}'
sleep 5
nr=$(q "SELECT COUNT() FROM Contract WHERE AccountId = '$acc' AND Status = 'Activated' AND MB_Do_Not_Renew__c = false" .result.totalSize)
ar=$(q "SELECT COUNT() FROM Asset WHERE AccountId = '$acc' AND DoesAutomaticallyRenew = true" .result.totalSize)
qs=$(q "SELECT Status, COUNT(Id) n FROM Quote WHERE OpportunityId = '$ren' GROUP BY Status" '[.result.records[] | "\(.Status):\(.n)"]')
echo "T7 $([ "$nr" = 0 ] && [ "$ar" = 0 ] && echo PASS || echo FAIL) | activated contracts still renewing: $nr, assets auto-renewing: $ar, renewal quotes: $qs"
