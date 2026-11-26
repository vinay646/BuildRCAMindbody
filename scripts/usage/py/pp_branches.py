import sys,re
x=open(sys.argv[1]).read()
vers=re.findall(r'<versions>(.*?)</versions>', x, re.S)
act=[v for v in vers if '<status>Active</status>' in v] or vers[-1:]
v=act[0]
print('VERSION', (re.search(r'<versionNumber>(.*?)</versionNumber>', v) or [0,'?'])[1])
steps=re.findall(r'<steps>(.*?)</steps>', v, re.S)
def g(t,s):
    m=re.search(r'<'+t+r'>(.*?)</'+t+r'>', s, re.S); return m.group(1) if m else ''
for s in steps:
    lab=g('label',s)
    if not re.search(r'prorat|term-defined|evergreen|pricing term|subscription price', lab, re.I): continue
    print(f"\n# {lab} | name={g('name',s)[:60]} | parent={g('parentStep',s)[:60]} | seq={g('sequenceNumber',s)} | type={g('stepType',s)}")
    ac=g('advancedCondition',s)
    if ac:
        print('  LOGIC', g('conditionLogic',ac))
        for c in re.findall(r'<criteria>(.*?)</criteria>', ac, re.S):
            print('   ', g('sequenceNumber',c), g('sourceFieldName',c), g('operator',c), g('value',c))
    for a,b in re.findall(r'<name>([\w-]+)</name>\s*<output>false</output>\s*<type>Parameter</type>\s*<value>(.*?)</value>', s): 
        if re.search(r'Date|Term|Count|Model|Prorat|Unit', a, re.I): print('   IN', a, '=', b)
    for a,b in re.findall(r'<name>([\w-]+)</name>\s*<output>true</output>\s*<type>\w+</type>\s*<value>(.*?)</value>', s): print('   OUT', a, '->', b)
