#!/usr/bin/env bash
# READ-ONLY: UI review for Account, Contact, Opportunity, Quote (layouts, record pages, compact layouts, fields).
set -uo pipefail
API="/services/data/v$ORG_API"
O="Account Contact Opportunity Quote"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
echo "== RECORD TYPES"; raw "SELECT SobjectType, Name, IsActive FROM RecordType WHERE SobjectType IN ('Account','Contact','Opportunity','Quote')"
echo "== FLEXIPAGES"; raw "SELECT DeveloperName, MasterLabel, EntityDefinitionId, Type, LastModifiedDate FROM FlexiPage WHERE EntityDefinitionId IN ('Account','Contact','Opportunity','Quote')" "--use-tooling-api"
echo "== LAYOUTS"; raw "SELECT Name, TableEnumOrId, LastModifiedDate FROM Layout WHERE TableEnumOrId IN ('Account','Contact','Opportunity','Quote')" "--use-tooling-api"
mkdir -p ui && cd ui
M=""; for o in $O; do M="$M --metadata Layout:$o-* --metadata CompactLayout:$o.* --metadata FlexiPage:*"; done
sf project retrieve start --api-version "$ORG_API" --metadata "Layout" --metadata "FlexiPage" --metadata "CompactLayout" --target-org target --target-metadata-dir md --unzip --wait 15 --json > r.json 2>&1 || true
jq -r '.result.messages // [] | .[] | "WARN \(.problem)"' r.json | head -5
cd ..
python3 - <<'PY'
import os,re,glob,json,subprocess
objs=["Account","Contact","Opportunity","Quote"]
root=[d for d in glob.glob("ui/md/**/layouts",recursive=True)]
print("layout dirs",root)
def fields_in(xml): return re.findall(r"<field>([^<]+)</field>",xml)
for o in objs:
    print(f"\n######## {o}")
    for f in sorted(glob.glob(f"ui/md/**/layouts/{o}-*.layout*",recursive=True)):
        x=open(f).read()
        secs=re.findall(r"<label>([^<]*)</label>",x)
        req=re.findall(r"<behavior>Required</behavior>\s*<field>([^<]+)</field>",x)
        rl=re.findall(r"<relatedList>([^<]+)</relatedList>",x)
        print("LAYOUT",os.path.basename(f),"| sections:",secs[:15],"| fields:",len(fields_in(x)),"| required:",req,"| related lists:",[r.split('.')[-1] for r in rl][:25])
        print("   fields:",fields_in(x))
    for f in sorted(glob.glob(f"ui/md/**/compactLayouts/{o}.*",recursive=True)):
        print("COMPACT",os.path.basename(f),fields_in(open(f).read()))
for f in sorted(glob.glob("ui/md/**/flexipages/*.flexipage*",recursive=True)):
    x=open(f).read()
    so=re.findall(r"<sobjectType>([^<]+)</sobjectType>",x)
    if not so or so[0] not in objs: continue
    comps=re.findall(r"<componentName>([^<]+)</componentName>",x)
    print("FLEXIPAGE",os.path.basename(f),so[0],"| components:",sorted(set(comps)))
PY
echo "== ASSIGNMENTS"; grep -h -A2 "<layoutAssignments>" ui/md/**/profiles/*.profile* 2>/dev/null | grep -E "Account-|Contact-|Opportunity-|Quote-" | sort | uniq -c | head -20
for o in $O; do
  echo "== $o CUSTOM FIELDS"; sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.custom) | {n: .name, l: .label, t: .type, req: ((.nillable|not) and .createable and (.defaultedOnCreate|not))}]'
done
