#!/usr/bin/env bash
# READ-ONLY QA for MR-100 Volume discount by hierarchy locations (pricing setup, location count, procedure, quotes).
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== PRICE ADJUSTMENT SCHEDULES"; raw "SELECT Id, Name, ScheduleType, AdjustmentMethod, IsActive, EffectiveFrom, EffectiveTo, CreatedBy.Name, CreatedDate, LastModifiedDate FROM PriceAdjustmentSchedule ORDER BY CreatedDate"
echo "== TIERS (non-QuantumBit schedules)"; raw "SELECT PriceAdjustmentSchedule.Name, Product2.ProductCode, ProductSellingModel.Name, LowerBound, UpperBound, TierType, TierValue, CurrencyIsoCode, EffectiveFrom, EffectiveTo FROM PriceAdjustmentTier WHERE CreatedDate >= 2026-11-01T00:00:00Z ORDER BY PriceAdjustmentSchedule.Name, Product2.ProductCode, ProductSellingModel.Name, LowerBound LIMIT 500"
echo "== TIER COUNT BY SCHEDULE / CREATED"; raw "SELECT PriceAdjustmentSchedule.Name s, CurrencyIsoCode c, COUNT(Id) n, MIN(CreatedDate) first, MAX(LastModifiedDate) last FROM PriceAdjustmentTier GROUP BY PriceAdjustmentSchedule.Name, CurrencyIsoCode"
echo "== LOCATION COUNT FIELDS"
for o in Account Opportunity Quote QuoteLineItem; do echo "$o $(sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Location|Volume|Hierarch";"i")) | {name, type, formula: .calculatedFormula}]')"; done
echo "== LOCATION COUNT FLOWS"
for name in $(sf data query --use-tooling-api --query "SELECT DeveloperName FROM FlowDefinition WHERE DeveloperName LIKE '%Location%' OR DeveloperName LIKE '%Volume%'" --target-org target --json | jq -r '.result.records[].DeveloperName'); do
  id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = '$name' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty')
  [ -z "$id" ] && { echo "-- $name: no active version"; continue; }
  echo "-- $name"
  sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target | jq -c 'def v: (.stringValue // .numberValue // (if .booleanValue == null then null else (.booleanValue|tostring) end) // .elementReference); .Metadata | {object: .start.object, type: .start.triggerType, when: .start.recordTriggerType, filters: [.start.filters[]? | "\(.field) \(.operator) \(.value|v)"], lookups: [.recordLookups[]? | {name, object, filterLogic, filters: [.filters[]? | "\(.field) \(.operator) \(.value|v)"]}], aggregates: [.collectionProcessors[]? | {name, type: .collectionProcessorType}], loops: [.loops[]? | .collectionReference], assignments: [.assignments[]? | [.assignmentItems[]? | "\(.assignToReference) \(.operator) \(.value|v)"]], formulas: [.formulas[]? | {name, expression}], updates: [.recordUpdates[]? | {object, ref: .inputReference, filters: [.filters[]? | "\(.field) \(.operator) \(.value|v)"], fields: [.inputAssignments[]? | "\(.field)=\(.value|v)"]}]}' | cut -c1-3500
done
echo "== VALUES: accounts with a location count, opportunities, quotes"
raw "SELECT Name, Account_Level__c, Root_Account__r.Name, Region__c FROM Account WHERE Account_Level__c != null ORDER BY CreatedDate DESC LIMIT 15"
echo "== PRICING PROCEDURES (retrieve)"
mkdir -p /tmp/pp && sf project retrieve start --metadata ExpressionSetDefinition --target-dir /tmp/pp --target-org target --json > /tmp/pp/r.json 2>&1
jq -r '.result.files[]?.fullName' /tmp/pp/r.json | sort -u
for f in $(grep -lis "PriceAdjustmentSchedule\|Volume" $(find /tmp/pp -name '*.expressionSetDefinition-meta.xml')); do
  python3 - "$f" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
print("##", sys.argv[1].split('/')[-1])
for v in re.findall(r"<versions>.*?</versions>", s, re.S):
    name=re.search(r"<fullName>(.*?)</fullName>", v).group(1)
    active=re.search(r"<status>(.*?)</status>", v); vn=re.search(r"<versionNumber>(.*?)</versionNumber>", v)
    steps=[st for st in re.findall(r"<steps>.*?</steps>", v, re.S) if "PriceAdjustmentScheduleId" in st or "Volume" in st]
    print(" version", vn and vn.group(1), name, "status=", active and active.group(1), "volume-ish steps:", len(steps))
    for st in steps:
        label=re.findall(r"<label>(.*?)</label>", st)[-1:]
        params={n:val for n,val in re.findall(r"<name>([^<]*)</name><output>[^<]*</output><type>[^<]*</type><value>([^<]*)</value>", st)}
        keep={k:params[k] for k in ("PriceAdjustmentScheduleId","LowerBound","UpperBound","Quantity","LookUpName","InputUnitPrice") if k in params}
        print("   step", label, keep)
    for var in re.findall(r"<variables>.*?</variables>", v, re.S):
        if re.search(r"PAS|Schedule|Location|Volume", var, re.I):
            print("   var", re.search(r"<name>(.*?)</name>", var).group(1), (re.search(r"<value>(.*?)</value>", var) or re.search(r"<type>(.*?)</type>", var)).group(1))
PY
done
echo "== CONTEXT DEFINITIONS: location / volume attributes and mappings"
mkdir -p /tmp/cd && sf project retrieve start --metadata ContextDefinition --target-dir /tmp/cd --target-org target --json > /tmp/cd/r.json 2>&1
for f in $(find /tmp/cd -name '*.contextDefinition-meta.xml'); do
  python3 - "$f" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
hits=set(re.findall(r"<title>([^<]*(?:Location|Volume|Hierarch)[^<]*)</title>", s, re.I))
maps=re.findall(r"<contextAttrHydrationDetails><objectName>([^<]*)</objectName><queryAttribute>([^<]*(?:Location|Volume|Hierarch)[^<]*)</queryAttribute></contextAttrHydrationDetails><contextAttribute>([^<]*)</contextAttribute>", s, re.I)
if hits or maps: print("##", sys.argv[1].split('/')[-1], "attributes:", sorted(hits), "mappings:", sorted(set(maps)))
PY
done
echo "== RECENT QUOTE LINES: list vs net price"
raw "SELECT Quote.QuoteNumber, Quote.Opportunity.Account.Name, Product2.ProductCode, ProductSellingModel.Name, Quantity, ListPrice, UnitPrice, NetUnitPrice, CreatedDate FROM QuoteLineItem WHERE Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT','MB-F-AIC','MB-APP') ORDER BY CreatedDate DESC LIMIT 25"
