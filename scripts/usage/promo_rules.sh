#!/usr/bin/env bash
# READ ONLY: rule objects; compare NewPromo vs SWITCH50 rulesets
sf sobject list --target-org target 2>/dev/null | grep -i 'rule' | grep -v -i -E 'Share$|Feed$|History$|ChangeEvent$|Pricing|Approval|Assignment|Escalation|Matching|Duplicate|Sharing|Validation|Workflow|AutoResponse|Configurator' | tr '\n' ' '; echo
for o in $(sf sobject list --target-org target 2>/dev/null | grep -i -E '^(Ruleset[A-Za-z]*|Rule(Version|Definition|Condition|Action|Group|Criteria|Item)[A-Za-z]*|BusinessRule[A-Za-z]*|ExpressionSet[A-Za-z]*)$' | grep -v -E 'Share$|Feed$|History$'); do
  echo "== $o"; sf data query --query "SELECT FIELDS(ALL) FROM $o ORDER BY CreatedDate DESC LIMIT 6" --target-org target --json 2>/dev/null | jq -c '.result.records[]? | del(.attributes,.OwnerId,.CreatedById,.LastModifiedById,.SystemModstamp,.IsDeleted,.LastViewedDate,.LastReferencedDate,.CurrencyIsoCode)' | cut -c1-500
done
