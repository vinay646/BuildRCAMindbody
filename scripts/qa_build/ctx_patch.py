#!/usr/bin/env python3
"""Adds the two context attributes the Mindbody Plans model reads to the org's RLM_SalesTransactionContext (active
version), mapped like the dev org but to QA's own Quote fields:
  MbHierarchyLocationCount (number) <- Quote.Location_count__c
  MbPriorSystem (string)            <- Quote.Prior_system__c
Usage: ctx_patch.py <retrieved context file>   (edits it in place; nothing else in the context changes)"""
import sys, copy
import xml.etree.ElementTree as ET
NS = 'http://soap.sforce.com/2006/04/metadata'; ET.register_namespace('', NS); n = lambda t: f'{{{NS}}}{t}'
WANT = {'MbHierarchyLocationCount': ('number', 'Location_count__c'), 'MbPriorSystem': ('string', 'Prior_system__c')}
path = sys.argv[1]; tree = ET.parse(path); root = tree.getroot()
ver = next(v for v in root.findall(n('contextDefinitionVersions')) if v.findtext(n('isActive')) == 'true')
st = next(x for x in ver.iter(n('contextNodes')) if x.findtext(n('title')) == 'SalesTransaction')
# reuse attributes that already read the same Quote field (QA has its own, e.g. PriorSystem__c)
_qm = next(m for m in ver.findall(n('contextMappings')) if m.findtext(n('title')) == 'QuoteEntitiesMapping')
_nm = next(x for x in _qm.findall(n('contextNodeMappings')) if x.findtext(n('contextNode')) == 'SalesTransaction')
for _m in _nm.findall(n('contextAttributeMappings')):
    _f = _m.findtext(n('contextAttrHydrationDetails/') + n('queryAttribute')) if False else (_m.find(n('contextAttrHydrationDetails')).findtext(n('queryAttribute')) if _m.find(n('contextAttrHydrationDetails')) is not None else None)
    for _name, (_t, _field) in list(WANT.items()):
        if _f and _f.lower() == _field.lower():
            _a = _m.findtext(n('contextAttribute'))
            _dt = next((a.findtext(n('dataType')) for a in st.findall(n('contextAttributes')) if a.findtext(n('title')) == _a), '?')
            print(f'REUSE {_name} -> existing attribute {_a} ({_dt}) already reads Quote.{_field}')
            WANT.pop(_name)
have = {a.findtext(n('title')) for a in st.findall(n('contextAttributes'))}
template = next(a for a in st.findall(n('contextAttributes')) if a.find(n('inheritedFrom')) is None) if any(a.find(n('inheritedFrom')) is None for a in st.findall(n('contextAttributes'))) else None
for name, (dtype, field) in WANT.items():
    if name in have:
        print('attribute exists:', name); continue
    a = ET.Element(n('contextAttributes'))
    tg = ET.SubElement(a, n('contextTags')); ET.SubElement(tg, n('title')).text = name
    for k, v in (('customMappingAllowed', 'false'), ('dataType', dtype), ('fieldType', 'input'), ('key', 'false'),
                 ('localizationDisabled', 'false'), ('title', name), ('transient', 'false'), ('value', 'false')):
        ET.SubElement(a, n(k)).text = v
    # keep schema order: contextAttributes come first in a contextNode
    idx = max(i for i, c in enumerate(list(st)) if c.tag == n('contextAttributes')) + 1
    st.insert(idx, a); print('attribute added:', name, dtype)
qm = next(m for m in ver.findall(n('contextMappings')) if m.findtext(n('title')) == 'QuoteEntitiesMapping')
nm = next(x for x in qm.findall(n('contextNodeMappings')) if x.findtext(n('contextNode')) == 'SalesTransaction')
mapped = {x.findtext(n('contextAttribute')) for x in nm.findall(n('contextAttributeMappings'))}
for name, (dtype, field) in WANT.items():
    if name in mapped:
        print('mapping exists:', name); continue
    m = ET.Element(n('contextAttributeMappings'))
    h = ET.SubElement(m, n('contextAttrHydrationDetails'))
    ET.SubElement(h, n('objectName')).text = 'Quote'; ET.SubElement(h, n('queryAttribute')).text = field
    ET.SubElement(m, n('contextAttribute')).text = name; ET.SubElement(m, n('contextInputAttributeName')).text = field
    idx = max(i for i, c in enumerate(list(nm)) if c.tag == n('contextAttributeMappings')) + 1
    nm.insert(idx, m); print('mapping added:', name, '<- Quote.' + field)
tree.write(path, xml_declaration=True, encoding='UTF-8')
