#!/usr/bin/env bash
# CREATES then DELETES test data in QA: MR-128 #3 - Enterprise on a quote whose account has no activated master contract should be blocked
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
mk() { sf data create record --sobject "$1" --values "$2" --target-org target --json 2>&1; }
D=$(date -u +%Y-%m-%d); E=$(date -u -d '+2 years -1 day' +%Y-%m-%d); S=$(date -u +%H%M%S)
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name LIKE 'North America%' AND IsActive = true LIMIT 1" | jq -r '.[0].Id')
PBE=$(q "SELECT Id, Product2Id, ProductSellingModel.Name FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ENT' AND Pricebook2Id = '$PB' AND IsActive = true")
echo "pricebook $PB enterprise entries $(echo "$PBE" | jq -c '[.[] | .ProductSellingModel.Name]')"
E1=$(echo "$PBE" | jq -c '[.[] | select(.ProductSellingModel.Name == "Term Monthly")][0] // .[0]')
DESC=$(sf sobject describe --sobject Account --target-org target --json 2>/dev/null); VERT=$(echo "$DESC" | jq -r ".result.fields[] | select(.name==\"Vertical__c\") | .picklistValues[0].value"); REG=$(echo "$DESC" | jq -r "[.result.fields[] | select(.name==\"Region__c\") | .picklistValues[].value] | (map(select(.==\"NA\")) + .)[0]"); echo "vertical $VERT region $REG"
R=$(mk Account "Name='QA TEST MR-128 $S' Account_Level__c=Corporate Vertical__c='$VERT' Region__c='$REG' BillingStreet='1 Test St' BillingCity=Austin BillingState=Texas BillingPostalCode=73301 BillingCountry='United States' ShippingStreet='1 Test St' ShippingCity=Austin ShippingState=Texas ShippingPostalCode=73301 ShippingCountry='United States'")
ACC=$(echo "$R" | jq -r '.result.id // empty'); [ -z "$ACC" ] && { echo "account error: $(echo "$R" | jq -r .message | head -c 400)"; exit 1; }
echo "account $ACC contracts: $(q "SELECT COUNT(Id) n FROM Contract WHERE AccountId = '$ACC'" | jq -r '.[0].n')"
OPP=$(mk Opportunity "Name='QA TEST MR-128 $S' AccountId=$ACC StageName=Prospecting CloseDate=$D Pricebook2Id=$PB" | jq -r '.result.id // empty')
R=$(mk Quote "Name='QA TEST MR-128' OpportunityId=$OPP Pricebook2Id=$PB RLM_TermMonths__c=24 StartDate=$D")
QT=$(echo "$R" | jq -r '.result.id // empty'); [ -z "$QT" ] && echo "quote error: $(echo "$R" | jq -r .message | head -c 400)"
R=$(mk QuoteLineItem "QuoteId=$QT Product2Id=$(echo "$E1" | jq -r .Product2Id) PricebookEntryId=$(echo "$E1" | jq -r .Id) Quantity=1 UnitPrice=0 StartDate=$D EndDate=$E BillingFrequency=Monthly")
echo "ADD ENTERPRISE LINE: status $(echo "$R" | jq -r .status) | $(echo "$R" | jq -r '.message // .result.id' | head -c 500)"
sleep 5; echo "enterprise lines on quote after: $(q "SELECT COUNT(Id) n FROM QuoteLineItem WHERE QuoteId = '$QT'" | jq -r '.[0].n')"
[ -n "$OPP" ] && sf data delete record --sobject Opportunity --record-id $OPP --target-org target --json >/dev/null 2>&1
sf data delete record --sobject Account --record-id $ACC --target-org target --json | jq -c '{cleanup: .status}'
