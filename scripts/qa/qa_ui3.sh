#!/usr/bin/env bash
# READ-ONLY: help text on custom fields, and fields per section on the record pages.
set -uo pipefail
API="/services/data/v$ORG_API"
for o in Account Contact Opportunity Quote; do
  echo "== HELP $o"; sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.custom) | {n: .name, l: .label, help: (.inlineHelpText // "-")}]'
done
mkdir -p ui3 && cd ui3
sf project retrieve start --api-version "$ORG_API" --metadata "FlexiPage:RLM_Account_Record_Page" --metadata "FlexiPage:RLM_Opportunity_Record_Page" --metadata "FlexiPage:RLM_Quote_Record_Page" --target-org target --target-metadata-dir md --unzip --wait 15 --json > r.json 2>&1 || true
cd ..
python3 - <<'PY'
import glob,os
import xml.etree.ElementTree as ET
ns={'m':'http://soap.sforce.com/2006/04/metadata'}
for f in sorted(glob.glob("ui3/md/**/flexipages/*.flexipage*",recursive=True)):
    t=ET.parse(f).getroot()
    regions={r.find('m:name',ns).text:r for r in t.findall('m:flexiPageRegions',ns)}
    def fields_of(facet):
        r=regions.get(facet); out=[]
        if r is None: return out
        for it in r.findall('m:itemInstances',ns):
            fi=it.find('m:fieldInstance',ns)
            if fi is not None: out.append(fi.find('m:fieldItem',ns).text.replace('Record.',''))
            ci=it.find('m:componentInstance',ns)
            if ci is not None:
                for p in ci.findall('m:componentInstanceProperties',ns):
                    if p.find('m:name',ns).text=='body': out+=fields_of(p.find('m:value',ns).text)
        return out
    print("\n##",os.path.basename(f).split('.')[0])
    for r in t.findall('m:flexiPageRegions',ns):
        for it in r.findall('m:itemInstances',ns):
            ci=it.find('m:componentInstance',ns)
            if ci is None or ci.find('m:componentName',ns).text!='flexipage:fieldSection': continue
            props={p.find('m:name',ns).text:(p.find('m:value',ns).text if p.find('m:value',ns) is not None else '') for p in ci.findall('m:componentInstanceProperties',ns)}
            label=props.get('label','').replace('@@@SFDC','').replace('SFDC@@@','').replace('_',' ')
            print(f"  [{label}] cols={props.get('columns','')} collapsed={props.get('isCollapsed', props.get('collapsed',''))} ->", fields_of(props.get('columns','')) if False else fields_of(it.find('m:componentInstance',ns).find('m:identifier',ns).text if False else '') or "")
            # field sections hold columns via 'columns' facet property
            cols=[p.find('m:value',ns).text for p in ci.findall('m:componentInstanceProperties',ns) if p.find('m:name',ns).text=='columns']
            for c in cols:
                r2=regions.get(c)
                if r2 is None: continue
                allf=[]
                for it2 in r2.findall('m:itemInstances',ns):
                    ci2=it2.find('m:componentInstance',ns)
                    if ci2 is not None:
                        for p in ci2.findall('m:componentInstanceProperties',ns):
                            if p.find('m:name',ns).text=='body': allf.append(fields_of(p.find('m:value',ns).text))
                print("      columns:",allf)
PY
