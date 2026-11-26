import sys,re
x=open(sys.argv[1]).read()
for ver in re.findall(r'<contextDefinitionVersions>(.*?)</contextDefinitionVersions>', x, re.S):
    act=re.search(r'<isActive>(.*?)</isActive>', ver[-400:]); vn=re.search(r'<versionNumber>(\d+)</versionNumber>', ver[-400:])
    print('CTXVERSION', vn.group(1) if vn else '?', 'active', act.group(1) if act else '?')
    for m in re.findall(r'<contextMappings>(.*?)</contextMappings>', ver, re.S):
        mname=re.findall(r'<title>(.*?)</title>', m)[-1:] 
        for nm in re.findall(r'<contextNodeMappings>(.*?)</contextNodeMappings>', m, re.S):
            node=re.search(r'<contextNode>(.*?)</contextNode>', nm); obj=re.search(r'<object>(.*?)</object>', nm)
            if not node or 'SalesTransactionItem' != node.group(1).split('/')[-1]: continue
            for am in re.findall(r'<contextAttributeMappings>(.*?)</contextAttributeMappings>', nm, re.S):
                a=re.search(r'<contextAttribute>(.*?)</contextAttribute>', am)
                if a and re.search(r'SubscriptionTerm$|StartDate$|EndDate$|PricingTermCount$|SellingModelType$|BillingFrequency$', a.group(1)):
                    src=re.search(r'<contextInputAttributeName>(.*?)</contextInputAttributeName>', am)
                    print('  MAP', mname, obj.group(1) if obj else '', a.group(1).split('/')[-1], '<-', src.group(1) if src else '(none)')
