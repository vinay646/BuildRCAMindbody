#!/usr/bin/env bash
# CHANGES test data (MR-122 amendment quote/opportunity on the MR103 Q2C04 account): amendment order path end to end; READ ONLY uplift setup
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
QID=0Q0hm0000007VThCAM
opp=$(q "SELECT OpportunityId FROM Quote WHERE Id = '$QID'" '.result.records[0].OpportunityId' | tr -d '"')
acc=$(q "SELECT AccountId FROM Opportunity WHERE Id = '$opp'" '.result.records[0].AccountId' | tr -d '"')
echo "assets before: $(q "SELECT Name, CurrentQuantity, Quantity FROM Asset WHERE AccountId = '$acc' AND Name = 'Ultimate' ORDER BY CreatedDate LIMIT 1" '.result.records[0] | del(.attributes)')"
sf data update record --sobject Quote --record-id $QID --values "Status='Presented'" --target-org target --json | jq -c '{presented: .status, message}'
sf data update record --sobject Opportunity --record-id $opp --values "StageName='Closed Won'" --target-org target --json | jq -c '{won: .status, message}'
for i in $(seq 1 20); do sleep 8; o=$(q "SELECT MB_Order__c, MB_Order_Error__c FROM Opportunity WHERE Id = '$opp'" '.result.records[0]'); [ "$(echo $o | jq -r '.MB_Order__c // .MB_Order_Error__c // empty')" ] && break; done
echo "opp: $o"
oid=$(echo $o | jq -r '.MB_Order__c // empty')
if [ -n "$oid" ]; then for i in $(seq 1 15); do sleep 8; s=$(q "SELECT OrderNumber, Status, ContractId, MB_Activation_Error__c, EffectiveDate FROM Order WHERE Id = '$oid'" '.result.records[0] | del(.attributes)'); echo "$s" | grep -q 'Activated\|Activation_Error__c":"' && break; done; echo "order: $s"; fi
sleep 20
echo "assets after: $(q "SELECT Name, CurrentQuantity, Quantity FROM Asset WHERE AccountId = '$acc' ORDER BY CreatedDate" '[.result.records[] | del(.attributes)]')"
echo "contracts: $(q "SELECT Id, Status, StartDate, EndDate FROM Contract WHERE AccountId = '$acc'" '[.result.records[] | del(.attributes)]')"
echo "== price revision policy"
sf sobject describe --sobject PriceRevisionPolicy --target-org target --json | jq -c '[.result.fields[] | select(.custom|not) | select(.name|test("^(Id|IsDeleted|CreatedById|CreatedDate|LastModifiedById|LastModifiedDate|SystemModstamp|OwnerId|LastViewedDate|LastReferencedDate)$")|not) | "\(.name):\(.type)\(if .picklistValues|length>0 then "=" + ([.picklistValues[].value]|join("/")) else "" end)"]'
echo "policies: $(q "SELECT FIELDS(STANDARD) FROM PriceRevisionPolicy LIMIT 5" '[.result.records[] | del(.attributes)]')"
echo "where used: $(for o in Product2 ProductSellingModelOption PricebookEntry Asset Contract QuoteLineItem OrderItem; do sf sobject describe --sobject $o --target-org target --json | jq -r --arg o $o '[.result.fields[] | select(.name|test("PriceRevision|Uplift";"i")) | "\($o).\(.name)"] | join(" ")'; done | tr '\n' ' ')"
