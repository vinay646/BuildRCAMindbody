#!/usr/bin/env bash
# READ-ONLY QA for MR-114 UI review: record pages (sections, fields, read-only, visibility), layouts, fields, templates.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
rm -rf ui && mkdir ui
sf project retrieve start --metadata "FlexiPage:RLM_Account_Record_Page" --metadata "FlexiPage:RLM_Opportunity_Record_Page" --metadata "FlexiPage:RLM_Quote_Record_Page" --metadata "FlexiPage:Contact_Record_Page1" --metadata "FlexiPage:Opportunity_Record_Page" \
  --metadata "Layout:Account-RLM Account Layout" --metadata "Layout:Opportunity-RLM Opportunity Layout" --metadata "Layout:Quote-RLM Quote Layout" --metadata "Layout:Contact-Contact Layout" \
  --target-org target --target-metadata-dir ui --unzip --wait 10 >/dev/null 2>&1
python3 - <<'PY'
import re, glob, os
def facets(s):
    # map facet name -> list of field items with behaviour and visibility
    out = {}
    for reg in re.findall(r"<flexiPageRegions>(.*?)</flexiPageRegions>", s, re.S):
        name = (re.search(r"<name>([^<]*)</name>\s*<type>(Facet|Region)</type>", reg) or [None, None])[1]
        items = []
        for it in re.findall(r"<itemInstances>(.*?)</itemInstances>", reg, re.S):
            fi = re.search(r"<fieldItem>([^<]*)</fieldItem>", it)
            beh = re.search(r"<name>uiBehavior</name>\s*<value>([^<]*)</value>", it)
            vis = "visibility-rule" if "<visibilityRule>" in it else ""
            if fi: items.append(f"{fi.group(1).replace('Record.','')}[{beh.group(1) if beh else '-'}]{('{'+vis+'}') if vis else ''}")
            comp = re.search(r"<componentName>([^<]*)</componentName>", it)
            if comp and not fi:
                props = dict(re.findall(r"<name>([^<]*)</name>\s*<value>([^<]*)</value>", it))
                label = props.get("label") or props.get("relatedListApiName") or props.get("parentFieldApiName") or props.get("title") or props.get("body") or ""
                items.append(f"<{comp.group(1)} {label}>{'{visibility-rule}' if vis else ''}")
        out[name] = items
    return out
for f in sorted(glob.glob("ui/**/*.flexipage", recursive=True)):
    s = open(f).read()
    print("\n=================== PAGE", os.path.basename(f))
    fs = facets(s)
    # section labels: fieldSection components have label property and body facet
    for sec in re.findall(r"<componentName>flexipage:fieldSection</componentName>", s): pass
    for it in re.findall(r"<itemInstances>\s*<componentInstance>(.*?)</componentInstance>\s*</itemInstances>", s, re.S):
        if "flexipage:fieldSection" in it:
            props = dict(re.findall(r"<name>([^<]*)</name>\s*<value>([^<]*)</value>", it))
            label = props.get("label"); body = props.get("columns") or ""
            cols = re.findall(r"<value>(Facet-[^<]*)</value>", it)
            fields = []
            for c in cols:
                for sub in fs.get(c, []):
                    m = re.match(r"<flexipage:column (Facet-[^>]*)>", sub)
                    if m: fields += fs.get(m.group(1), [])
                    elif not sub.startswith("<flexipage:column"): fields.append(sub)
                # columns are components inside the columns facet
                for sub in re.findall(r"Facet-[\w-]+", " ".join(fs.get(c, []))):
                    fields += fs.get(sub, [])
            print(f"  SECTION {label}: {', '.join(dict.fromkeys(fields))}")
    comps = [i for v in fs.values() for i in v if i.startswith("<") and "fieldSection" not in i and "flexipage:column" not in i]
    print("  COMPONENTS:", "; ".join(dict.fromkeys(comps))[:2500])
for f in sorted(glob.glob("ui/**/*.layout", recursive=True)):
    s = open(f).read()
    print("\n=================== LAYOUT", os.path.basename(f))
    for sec in re.findall(r"<layoutSections>(.*?)</layoutSections>", s, re.S):
        lab = (re.search(r"<label>([^<]*)</label>", sec) or [None, ""])[1]
        flds = re.findall(r"<field>([^<]*)</field>", sec)
        print(f"  SECTION {lab}: {', '.join(flds)}")
    rl = re.findall(r"<relatedList>([^<]*)</relatedList>", s)
    print("  RELATED LISTS:", ", ".join(rl))
    dup = [x for x in set(rl) if rl.count(x) > 1]
    print("  DUPLICATE RELATED LISTS:", dup)
PY
echo; echo "== Account fields: required (not nillable) and Test field"
sf api request rest "$API/sobjects/Account/describe" --target-org target | jq -c '[.fields[] | select(.name|test("^(Account_Level__c|Vertical__c|Region__c|Contract_Type__c|Test__c|Resolved_Payer_Id__c)$")) | {n: .name, t: .type, nillable, restricted: .restrictedPicklist, values: [.picklistValues[]?.value]}]'
echo "== Opportunity Location Count / Region"
sf api request rest "$API/sobjects/Opportunity/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Location_count__c|^Region__c")) | {n: .name, t: .type, calc: .calculated, f: .calculatedFormula, updateable}]'
echo "== quote templates"
q "SELECT Name, IsActive, IsDefault, UsageType, TokenMappingType FROM DocumentTemplate" 2>/dev/null
q "SELECT Name, IsActive FROM QuoteTemplateRichTextData" 2>/dev/null | head -c 300; echo
