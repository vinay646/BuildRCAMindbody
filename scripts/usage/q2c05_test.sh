#!/usr/bin/env bash
# CREATES test amendment / renewal quotes on the MR103 Q2C04 test account: MR-122 opportunity creation (T1, T3, T4)
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
acc=$(q "SELECT Id FROM Account WHERE Name LIKE 'MR103 Q2C04%' LIMIT 1" '.result.records[0].Id' | tr -d '"')
a=$(q "SELECT Id FROM Asset WHERE AccountId = '$acc' AND Name = 'Ultimate' ORDER BY CreatedDate LIMIT 1" '.result.records[0].Id' | tr -d '"')
sf data update record --sobject Asset --record-id $a --values "RenewalTerm=12 RenewalTermUnit=Months" --target-org target >/dev/null 2>&1
d=$(date -u -d '+1 day' +%Y-%m-%dT00:00:00Z)
amend=$(sf api request rest "$API/actions/standard/initiateAmendment" --method POST --body "{\"inputs\":[{\"amendAssetIds\":[\"$a\"],\"amendStartDate\":\"$d\",\"quantityChange\":1,\"amendOutputType\":\"Quote\"}]}" --target-org target 2>&1 | jq -r '.[0].outputValues.amendRecordId // .[0].errors[0].message')
echo "amendment quote: $amend"; sleep 45
o=$(q "SELECT OpportunityId, Opportunity.Name, Opportunity.Type, Opportunity.SyncedQuoteId, Opportunity.CloseDate, Opportunity.Amount FROM Quote WHERE Id = '$amend'" '.result.records[0]')
echo "T1 $(echo $o | jq -r 'if .OpportunityId and .Opportunity.Type == "Add Location" then "PASS" else "FAIL" end') $(echo $o | jq -c '{opp: .Opportunity.Name, type: .Opportunity.Type, synced: (.Opportunity.SyncedQuoteId != null), close: .Opportunity.CloseDate, amount: .Opportunity.Amount}')"
r1=$(sf api request rest "$API/actions/standard/initiateRenewal" --method POST --body "{\"inputs\":[{\"renewAssetIds\":[\"$a\"],\"renewOutputType\":\"Quote\"}]}" --target-org target 2>&1 | jq -r '.[0].outputValues.renewRecordId // .[0].errors[0].message')
echo "renewal quote: $r1"; sleep 45
o=$(q "SELECT OpportunityId, Opportunity.Name, Opportunity.Type, Opportunity.OwnerId FROM Quote WHERE Id = '$r1'" '.result.records[0]')
echo "T3 $(echo $o | jq -r 'if .Opportunity.Type == "Renewal" then "PASS" else "FAIL" end') $(echo $o | jq -c '{opp: .Opportunity.Name, type: .Opportunity.Type}')"
r2=$(sf api request rest "$API/actions/standard/initiateRenewal" --method POST --body "{\"inputs\":[{\"renewAssetIds\":[\"$a\"],\"renewOutputType\":\"Quote\"}]}" --target-org target 2>&1 | jq -r '.[0].outputValues.renewRecordId // .[0].errors[0].message')
echo "second renewal quote: $r2"; sleep 45
o2=$(q "SELECT OpportunityId FROM Quote WHERE Id = '$r2'" '.result.records[0].OpportunityId')
echo "T4 $([ "$o2" = "$(echo $o | jq -c .OpportunityId)" ] && echo PASS || echo FAIL) (same renewal opportunity: $o2) | open renewals: $(q "SELECT COUNT() FROM Opportunity WHERE AccountId = '$acc' AND Type = 'Renewal' AND IsClosed = false" .result.totalSize)"
