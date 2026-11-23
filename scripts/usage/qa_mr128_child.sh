#!/usr/bin/env bash
# CREATES then DELETES test data in QA: MR-128 #3 for child accounts - A: child of a top account with no master contract (expect blocked); B: child of a top account with an activated master contract (expect allowed)
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
mk() { sf data create record --sobject "$1" --values "$2" --target-org target --json 2>&1; }
D=$(date -u +%Y-%m-%d); E=$(date -u -d '+2 years -1 day' +%Y-%m-%d); S=$(date -u +%H%M%S)
addr() { echo "BillingStreet='$1 Test St' BillingCity=Austin BillingState=Texas BillingPostalCode=73301 BillingCountry='United States' ShippingStreet='$1 Test St' ShippingCity=Austin ShippingState=Texas ShippingPostalCode=73301 ShippingCountry='United States'"; }
#ADDR="BillingStreet='1 Test St' BillingCity=Austin BillingState=Texas BillingPostalCode=73301 BillingCountry='United States' ShippingStreet='1 Test St' ShippingCity=Austin ShippingState=Texas ShippingPostalCode=73301 ShippingCountry='United States'"
PB=$(q "SELECT Id FROM Pricebook2 WHERE Name LIKE 'North America%' AND IsActive = true LIMIT 1" | jq -r '.[0].Id')
E1=$(q "SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ENT' AND Pricebook2Id = '$PB' AND IsActive = true AND ProductSellingModel.Name = 'Term Monthly' LIMIT 1" | jq -c '.[0]')
CLEAN=()
try() { # $1 label, $2 child account id
  OPP=$(mk Opportunity "Name='QA TEST MR-128 $1 $S' AccountId=$2 StageName=Prospecting CloseDate=$D Pricebook2Id=$PB" | jq -r '.result.id // empty'); CLEAN+=("Opportunity:$OPP")
  R=$(mk Quote "Name='QA TEST MR-128 $1' OpportunityId=$OPP Pricebook2Id=$PB RLM_TermMonths__c=24 StartDate=$D"); QT=$(echo "$R" | jq -r '.result.id // empty')
  [ -z "$QT" ] && { echo "$1 quote error: $(echo "$R" | jq -r .message | head -c 300)"; return; }
  R=$(mk QuoteLineItem "QuoteId=$QT Product2Id=$(echo "$E1" | jq -r .Product2Id) PricebookEntryId=$(echo "$E1" | jq -r .Id) Quantity=1 UnitPrice=0 StartDate=$D EndDate=$E BillingFrequency=Monthly")
  echo "$1 ADD ENTERPRISE: status $(echo "$R" | jq -r .status) | $(echo "$R" | jq -r '.message // "line added"' | head -c 300) | lines on quote: $(q "SELECT COUNT(Id) n FROM QuoteLineItem WHERE QuoteId = '$QT'" | jq -r '.[0].n')"
}
# A: new top account (no contracts) + child
TOPA=$(mk Account "Name='QA TEST MR-128 TopA $S' Account_Level__c=Corporate Vertical__c=Fitness Region__c=NA $(addr "1$S")" | jq -r '.result.id // empty')
R=$(mk Account "Name='QA TEST MR-128 ChildA $S' Account_Level__c=Region ParentId=$TOPA Vertical__c=Fitness Region__c=NA $(addr "2$S")"); CHA=$(echo "$R" | jq -r '.result.id // empty')
[ -z "$CHA" ] && echo "childA error: $(echo "$R" | jq -r .message | head -c 300)"
echo "A: top $TOPA contracts $(q "SELECT COUNT(Id) n FROM Contract WHERE AccountId = '$TOPA'" | jq -r '.[0].n'), child $CHA"
[ -n "$CHA" ] && try A "$CHA"
# B: top account with an activated master contract
TOPB=$(q "SELECT Id, Name FROM Account WHERE Name LIKE 'Rock%Roll%' AND ParentId = null LIMIT 1")
TB=$(echo "$TOPB" | jq -r '.[0].Id // empty')
echo "B: top $(echo "$TOPB" | jq -c '.[0]') activated contracts $(q "SELECT ContractNumber, Status FROM Contract WHERE AccountId = '$TB' AND Status = 'Activated'" | jq -c '[.[].ContractNumber]')"
if [ -n "$TB" ]; then
  R=$(mk Account "Name='QA TEST MR-128 ChildB $S' Account_Level__c=Region ParentId=$TB Vertical__c=Fitness Region__c=NA $(addr "3$S")"); CHB=$(echo "$R" | jq -r '.result.id // empty')
  [ -z "$CHB" ] && echo "childB error: $(echo "$R" | jq -r .message | head -c 300)" || try B "$CHB"
fi
sleep 3
for c in "${CLEAN[@]}"; do [ -n "${c#*:}" ] && sf data delete record --sobject "${c%%:*}" --record-id "${c#*:}" --target-org target --json >/dev/null 2>&1; done
for a in $CHB $CHA $TOPA; do echo "cleanup $a: $(sf data delete record --sobject Account --record-id $a --target-org target --json 2>&1 | jq -r .status)"; done
