#!/usr/bin/env bash
# CHANGES org: refreshes the rate card decision tables; adds asset rate card entries to the MBUsage test assets (rating needs them) and re-runs rating
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)]'; }
for dn in $(q "SELECT DeveloperName FROM DecisionTable WHERE DeveloperName LIKE '%Rate%' OR MasterLabel LIKE '%Rate%'" | jq -r '.[].DeveloperName'); do
  echo "refresh $dn: $(sf api request rest "$API/actions/standard/refreshDecisionTable" --method POST --body "{\"inputs\":[{\"DecisionTableApiName\":\"$dn\"}]}" --target-org target 2>&1 | jq -c '.[0].outputValues' 2>/dev/null)"
done
ACC=$(q "SELECT Id FROM Account WHERE Name LIKE 'MBUsage-%' ORDER BY CreatedDate DESC LIMIT 1" | jq -r '.[0].Id')
for row in $(q "SELECT Id, Product2Id FROM Asset WHERE AccountId = '$ACC'" | jq -c '.[]'); do
  A=$(echo "$row" | jq -r .Id); P=$(echo "$row" | jq -r .Product2Id)
  E=$(q "SELECT Id, RateCardId, UsageResourceId, RateUnitOfMeasureId FROM RateCardEntry WHERE ProductId = '$P' AND Status = 'Active' AND RateCard.Name = 'Mindbody Usage Base' LIMIT 1" | jq -c '.[0]')
  [ "$(q "SELECT Id FROM AssetRateCardEntry WHERE AssetId = '$A'" | jq length)" = "0" ] && echo "arce $A: $(sf api request rest "$API/sobjects/AssetRateCardEntry" --method POST --body "$(echo "$E" | jq -c --arg a "$A" '{AssetId: $a, RateCardEntryId: .Id, RateCardId, UsageResourceId, RateUnitOfMeasureId, StartDate: "2026-10-11T00:00:00Z", EndDate: "2027-10-10T23:59:59Z", BindingObjectRateOrder: 1}')" --target-org target 2>&1 | tr -d '\n' | head -c 250)"
done
sleep 60
echo "== Ratable summary flow: $(sf api request rest "$API/actions/custom/flow/runtime_industries_usage__UseRateSum" --method POST --body '{"inputs":[{}]}' --target-org target 2>&1 | jq -c '.[0].isSuccess' 2>/dev/null)"; sleep 150
echo "RATABLE $(q "SELECT UsageResource.Code, Status, OverageQuantity, NetUnitRate, TotalAmount, ErrorDescription FROM UsageRatableSummary WHERE AccountId = '$ACC' AND StartDateTime < 2026-11-01T00:00:00Z" | sed 's/"attributes":{[^}]*},//g')"
