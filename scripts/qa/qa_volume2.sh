#!/usr/bin/env bash
# READ-ONLY: MR-100 follow-up - pricing procedure volume step, context mappings, location counts on quotes.
set -uo pipefail
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== EXPRESSION SETS"; raw "SELECT Id, DeveloperName, MasterLabel, LastModifiedDate FROM ExpressionSetDefinition ORDER BY LastModifiedDate DESC LIMIT 20"
raw "SELECT ExpressionSetDefinition.DeveloperName, DeveloperName, VersionNumber, Status, LastModifiedDate FROM ExpressionSetDefinitionVersion WHERE LastModifiedDate >= 2026-11-01T00:00:00Z ORDER BY LastModifiedDate DESC"
echo "== CONTEXT DEFINITIONS"; raw "SELECT DeveloperName, LastModifiedDate FROM ContextDefinition ORDER BY LastModifiedDate DESC LIMIT 10"
args=""; for n in $(sf data query --query "SELECT DeveloperName FROM ExpressionSetDefinition WHERE LastModifiedDate >= 2026-11-01T00:00:00Z" --target-org target --json | jq -r '.result.records[].DeveloperName'); do args="$args --metadata ExpressionSetDefinition:$n"; done
for n in $(sf data query --query "SELECT DeveloperName FROM ContextDefinition WHERE LastModifiedDate >= 2026-10-25T00:00:00Z" --target-org target --json | jq -r '.result.records[].DeveloperName'); do args="$args --metadata ContextDefinition:$n"; done
echo "retrieve:$args"
mkdir -p /tmp/md && sf project retrieve start $args --target-dir /tmp/md --target-org target --json > /tmp/md/r.json 2>&1; jq -c '{status, message, files: [.result.files[]? | "\(.type):\(.fullName) \(.state)"]}' /tmp/md/r.json | cut -c1-1500
for f in $(find /tmp/md -name '*.expressionSetDefinition-meta.xml'); do
  python3 - "$f" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
print("##", sys.argv[1].split('/')[-1])
for v in re.findall(r"<versions>.*?</versions>", s, re.S):
    name=re.search(r"<fullName>(.*?)</fullName>", v).group(1)
    st_=re.search(r"<status>(.*?)</status>", v); vn=re.search(r"<versionNumber>(.*?)</versionNumber>", v)
    steps=[st for st in re.findall(r"<steps>.*?</steps>", v, re.S) if "PriceAdjustmentScheduleId" in st]
    print(" version", vn and vn.group(1), name, "status=", st_ and st_.group(1), "tier steps:", len(steps))
    for st in steps:
        label=re.findall(r"<label>(.*?)</label>", st)[-1:]
        params={n:val for n,val in re.findall(r"<name>([^<]*)</name><output>[^<]*</output><type>[^<]*</type><value>([^<]*)</value>", st)}
        print("   step", label, {k:params.get(k) for k in ("PriceAdjustmentScheduleId","LowerBound","UpperBound","Quantity","LookUpName","InputUnitPrice")})
    for var in re.findall(r"<variables>.*?</variables>", v, re.S):
        if re.search(r"Location|Volume|PAS", var, re.I):
            print("   var", re.search(r"<name>(.*?)</name>", var).group(1), "|", (re.search(r"<value>(.*?)</value>", var) or re.search(r"<type>(.*?)</type>", var)).group(1))
PY
done
for f in $(find /tmp/md -name '*.contextDefinition-meta.xml'); do
  python3 - "$f" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
hits=sorted(set(re.findall(r"<title>([^<]*(?:Location|Volume|Hierarch)[^<]*)</title>", s, re.I)))
maps=sorted(set(re.findall(r"<objectName>([^<]*)</objectName><queryAttribute>([^<]*(?:Location|Volume|Hierarch)[^<]*)</queryAttribute></contextAttrHydrationDetails><contextAttribute>([^<]*)</contextAttribute>", s, re.I)))
print("##", sys.argv[1].split('/')[-1], "attributes:", hits, "mappings:", maps)
PY
done
echo "== LOCATION COUNTS ON RECENT QUOTES / OPPORTUNITIES"
raw "SELECT QuoteNumber, Location_count__c, Opportunity.Location_count__c, Opportunity.Account.Name, Opportunity.Account.Root_Account__r.Name, CreatedDate FROM Quote ORDER BY CreatedDate DESC LIMIT 12"
raw "SELECT Quote.QuoteNumber, Product2.ProductCode, Quantity, Location_count__c, ListPrice, NetUnitPrice FROM QuoteLineItem WHERE Quote.QuoteNumber IN ('00000001','00000034','00000025','00000035')"
echo "== WHAT FEEDS Quote/QLI Location_count__c (flows)"
sf data query --use-tooling-api --query "SELECT DeveloperName, ActiveVersion.VersionNumber, LastModifiedDate FROM FlowDefinition WHERE LastModifiedDate >= 2026-11-10T00:00:00Z" --target-org target --json | jq -c '[.result.records[] | "\(.DeveloperName) v\(.ActiveVersion.VersionNumber) \(.LastModifiedDate[0:16])"]'
echo "== ACTIVE CORE-TIER ASSETS (Apex Dynamics hierarchy)"
raw "SELECT Account.Name, Product2.ProductCode, CurrentQuantity, Status, LifecycleEndDate FROM Asset WHERE Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT') ORDER BY Account.Name LIMIT 40"
