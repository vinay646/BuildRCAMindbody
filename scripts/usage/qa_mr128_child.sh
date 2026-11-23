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
mka() { # $1 name, $2 level, $3 parent or "", $4 street; prints raw response
  sf api request rest "/services/data/v$ORG_API/sobjects/Account" --method POST --header "Sforce-Duplicate-Rule-Header: allowSave=true" --body "$(jq -nc --arg n "$1" --arg l "$2" --arg p "$3" --arg st "$4" '{Name:$n, Account_Level__c:$l, Vertical__c:"Fitness", Region__c:"NA", BillingStreet:$st, BillingCity:"Austin", BillingState:"Texas", BillingPostalCode:"73301", BillingCountry:"United States", ShippingStreet:$st, ShippingCity:"Austin", ShippingState:"Texas", ShippingPostalCode:"73301", ShippingCountry:"United States"} + (if $p == "" then {} else {ParentId:$p} end)')" --target-org target 2>&1
}
try() { # $1 label, $2 child account id
  OPP=$(mk Opportunity "Name='QA TEST MR-128 $1 $S' AccountId=$2 StageName=Prospecting CloseDate=$D Pricebook2Id=$PB" | jq -r '.result.id // empty'); CLEAN+=("Opportunity:$OPP")
  R=$(mk Quote "Name='QA TEST MR-128 $1' OpportunityId=$OPP Pricebook2Id=$PB RLM_TermMonths__c=24 StartDate=$D"); QT=$(echo "$R" | jq -r '.result.id // empty')
  [ -z "$QT" ] && { echo "$1 quote error: $(echo "$R" | jq -r .message | head -c 300)"; return; }
  R=$(mk QuoteLineItem "QuoteId=$QT Product2Id=$(echo "$E1" | jq -r .Product2Id) PricebookEntryId=$(echo "$E1" | jq -r .Id) Quantity=1 UnitPrice=0 StartDate=$D EndDate=$E BillingFrequency=Monthly")
  echo "$1 ADD ENTERPRISE: status $(echo "$R" | jq -r .status) | $(echo "$R" | jq -r '.message // "line added"' | head -c 300) | lines on quote: $(q "SELECT COUNT(Id) n FROM QuoteLineItem WHERE QuoteId = '$QT'" | jq -r '.[0].n')"
}
# A: new top account (no contracts) + child
TOPA=$(mka "QA TEST MR-128 TopA $S" Corporate "" "1$S Test St" | jq -r '.id // empty')
R=$(mka "QA TEST MR-128 ChildA $S" Region "$TOPA" "2$S Test St"); CHA=$(echo "$R" | jq -r '.id // empty')
[ -z "$CHA" ] && echo "childA error: $(echo "$R" | jq -r ".[0].message? // ." | head -c 300)"
echo "A: top $TOPA contracts $(q "SELECT COUNT(Id) n FROM Contract WHERE AccountId = '$TOPA'" | jq -r '.[0].n'), child $CHA"
[ -n "$CHA" ] && try A "$CHA"
# B: top account with an activated master contract
TOPB=$(q "SELECT Id, Name FROM Account WHERE Name LIKE 'Rock%Roll%' AND ParentId = null LIMIT 1")
TB=$(echo "$TOPB" | jq -r '.[0].Id // empty')
echo "B: top $(echo "$TOPB" | jq -c '.[0]') activated contracts $(q "SELECT ContractNumber, Status FROM Contract WHERE AccountId = '$TB' AND Status = 'Activated'" | jq -c '[.[].ContractNumber]')"
if [ -n "$TB" ]; then
  R=$(mka "QA TEST MR-128 ChildB $S" Region "$TB" "3$S Test St"); CHB=$(echo "$R" | jq -r '.id // empty')
  sleep 5; echo "B child fields: $(sf data query --query "SELECT FIELDS(CUSTOM) FROM Account WHERE Id = '$CHB' LIMIT 1" --target-org target --json 2>/dev/null | jq -c '.result.records[0] | with_entries(select(.value != null and .value != false and (.key|test("Root|Master|Parent|Top|Contract";"i"))))')"
  echo "B top fields: $(sf data query --query "SELECT FIELDS(CUSTOM) FROM Account WHERE Id = '$TB' LIMIT 1" --target-org target --json 2>/dev/null | jq -c '.result.records[0] | with_entries(select(.value != null and .value != false and (.key|test("Root|Master|Parent|Top|Contract";"i"))))')"
  echo "B contracts: $(sf data query --query "SELECT FIELDS(CUSTOM), ContractNumber, Status FROM Contract WHERE AccountId = '$TB' LIMIT 5" --target-org target --json 2>/dev/null | jq -c '[.result.records[] | with_entries(select(.value != null and .value != false and (.key|test("Number|Status|Master|Type";"i"))))]')"
  try TOP "$TB"
  [ -z "$CHB" ] && echo "childB error: $(echo "$R" | jq -r ".[0].message? // ." | head -c 300)" || try B "$CHB"
fi
sleep 3
for c in "${CLEAN[@]}"; do [ -n "${c#*:}" ] && sf data delete record --sobject "${c%%:*}" --record-id "${c#*:}" --target-org target --json >/dev/null 2>&1; done
for a in $CHB $CHA $TOPA; do echo "cleanup $a: $(sf data delete record --sobject Account --record-id $a --target-org target --json 2>&1 | jq -r .status)"; done
