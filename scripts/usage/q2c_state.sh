#!/usr/bin/env bash
# READ ONLY: what exists for the Q2C automations (MR-118..122)
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
echo "flows: $(q "SELECT ApiName, TriggerObjectOrEventLabel, IsActive, LastModifiedBy FROM FlowDefinitionView WHERE TriggerObjectOrEventLabel IN ('Quote','Opportunity','Order','Contract','Asset') OR ApiName LIKE '%Sync%' OR ApiName LIKE '%Order%' OR ApiName LIKE '%Renew%'" '[.result.records[] | "\(.ApiName)|\(.TriggerObjectOrEventLabel)|\(.IsActive)|\(.LastModifiedBy)"]')"
echo "quote status: $(sf sobject describe --sobject Quote --target-org target --json | jq -c '[.result.fields[] | select(.name=="Status") | .picklistValues[] | select(.active) | .value]')"
echo "opp stages: $(sf sobject describe --sobject Opportunity --target-org target --json | jq -c '[.result.fields[] | select(.name=="StageName") | .picklistValues[] | select(.active) | .value]')"
for o in Quote Opportunity QuoteLineItem OpportunityLineItem Order Contract; do echo "$o custom: $(sf sobject describe --sobject $o --target-org target --json | jq -c '[.result.fields[] | select(.custom) | .name]')"; done
echo "opp synced quotes: $(q "SELECT COUNT() FROM Opportunity WHERE SyncedQuoteId != null" '.result.totalSize') | orders: $(q "SELECT Status, COUNT(Id) n FROM Order GROUP BY Status" '[.result.records[] | "\(.Status):\(.n)"]') | contracts: $(q "SELECT Status, COUNT(Id) n FROM Contract GROUP BY Status" '[.result.records[] | "\(.Status):\(.n)"]') | assets: $(q "SELECT COUNT() FROM Asset" '.result.totalSize')"
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
sf project retrieve start --metadata "Settings:RevenueManagement" --metadata "Settings:Order" --metadata "Settings:Quote" --target-org target >/dev/null 2>&1
for f in force-app/main/default/settings/*.xml; do echo "== $(basename $f)"; grep -o "<[a-zA-Z]*>[^<]\{1,40\}</[a-zA-Z]*>" $f | tr '\n' ' '; echo; done
