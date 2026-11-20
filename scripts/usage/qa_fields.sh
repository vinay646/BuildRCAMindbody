#!/usr/bin/env bash
# READ ONLY: QA fields Prior system / Location count on Quote and Opportunity
for o in Quote Opportunity; do
  sf sobject describe --sobject $o --target-org target --json | jq -c '.result.fields[] | select(.name=="Prior_system__c" or .name=="Prior_System__c" or .name=="Location_count__c") | {name, type, calculated, calculatedFormula, label, picklist: [.picklistValues[]?.value]}'
done
sf data query --query "SELECT Prior_system__c, Location_count__c, COUNT(Id) n FROM Quote GROUP BY Prior_system__c, Location_count__c LIMIT 15" --target-org target 2>&1 | tail -18
