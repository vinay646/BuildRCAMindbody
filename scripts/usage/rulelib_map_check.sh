#!/usr/bin/env bash
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
OBJS=$(sf api request rest "$API/sobjects" --target-org target | jq -r '[.sobjects[] | select(.name|test("RuleLib|TagMap|CustomTag|RuleLibrary";"i")) | select(.name|test("Feed|History|Share|ChangeEvent")|not) | .name] | join(" ")')
echo "OBJECTS $OBJS"
for o in $OBJS; do
  echo "== $o fields: $(sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.createable or .updateable) | {n: .name, t: .type, req: ((.nillable|not) and .createable), ref: .referenceTo, pl: ([.picklistValues[]?.value] | if length>0 and length<40 then . else null end)}]' | head -c 2500)"
  echo "   rows: $(q "SELECT FIELDS(STANDARD) FROM $o LIMIT 5" | jq -c '[.[]? | with_entries(select(.value != null and (.key|test("Created|LastModified|System|IsDeleted|LastViewed|LastReferenced|Owner|CurrencyIsoCode")|not)))]' | head -c 1500)"
done
