#!/usr/bin/env bash
# READ-ONLY: fields placed on the Lightning record pages (Dynamic Forms) and page activation.
set -uo pipefail
mkdir -p ui2 && cd ui2
sf project retrieve start --api-version "$ORG_API" --metadata "FlexiPage:RLM_Account_Record_Page" --metadata "FlexiPage:RLM_Opportunity_Record_Page" --metadata "FlexiPage:RLM_Quote_Record_Page" --metadata "FlexiPage:RLM_Collections_Account_Record_Page" --metadata "CustomApplication" --metadata "CompactLayout" --target-org target --target-metadata-dir md --unzip --wait 15 --json > r.json 2>&1 || true
cd ..
python3 - <<'PY'
import re,glob,os
for f in sorted(glob.glob("ui2/md/**/flexipages/*.flexipage*",recursive=True)):
    x=open(f).read()
    print("\n##",os.path.basename(f))
    # facets with field sections: print section labels + fields in order
    for m in re.finditer(r"<fieldInstance>.*?<fieldItem>([^<]+)</fieldItem>.*?</fieldInstance>",x,re.S): pass
    fields=re.findall(r"<fieldItem>Record\.([^<]+)</fieldItem>",x)
    labels=re.findall(r"<name>label</name>\s*<value>([^<]+)</value>",x)
    print("section labels:",labels[:30])
    print("fields:",fields)
    rls=re.findall(r"<name>relatedListApiName</name>\s*<value>([^<]+)</value>",x)
    print("related lists:",rls)
    tabs=re.findall(r"<name>title</name>\s*<value>([^<]+)</value>",x)
    print("tabs:",tabs)
for f in sorted(glob.glob("ui2/md/**/applications/*.app*",recursive=True)):
    x=open(f).read()
    ov=re.findall(r"<actionOverrides>.*?<content>([^<]+)</content>.*?<pageOrSobjectType>([^<]+)</pageOrSobjectType>.*?</actionOverrides>",x,re.S)
    ov=[o for o in ov if o[1] in ("Account","Opportunity","Quote","Contact")]
    pa=re.findall(r"<profileActionOverrides>.*?<content>([^<]+)</content>.*?<pageOrSobjectType>([^<]+)</pageOrSobjectType>.*?</profileActionOverrides>",x,re.S)
    pa=[o for o in pa if o[1] in ("Account","Opportunity","Quote","Contact")]
    if ov or pa: print("APP",os.path.basename(f),"overrides:",sorted(set(ov)),"profile overrides:",sorted(set(pa))[:10])
for f in sorted(glob.glob("ui2/md/**/compactLayouts/*",recursive=True)):
    b=os.path.basename(f)
    if b.split('.')[0] in ("Account","Contact","Opportunity","Quote"):
        print("COMPACT",b,re.findall(r"<fields>([^<]+)</fields>",open(f).read()))
for f in glob.glob("ui2/md/**/objects/*.object*",recursive=True): print("OBJ",f)
PY
