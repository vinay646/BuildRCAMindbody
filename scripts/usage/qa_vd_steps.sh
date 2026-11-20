#!/usr/bin/env bash
# READ ONLY: full inputs of the VolumeDiscount steps and the constants/variables of the active pricing procedure versions
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
sf project retrieve start --metadata "ExpressionSetDefinition:RLM_DefaultPricingProcedure" --target-org target >/dev/null 2>&1
f=$(find . -name "RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"); echo "file $f"
python3 - "$f" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
for v in re.findall(r'<versions>.*?</versions>', s, re.S):
    st = re.search(r'<status>(\w+)</status>', v).group(1); fn = re.search(r'<fullName>([^<]+)</fullName>', v).group(1)
    if st != 'Active': continue
    print('\n#### ACTIVE', fn, 'end', (re.search(r'<endDate>([^<]+)</endDate>', v) or [None, None])[1])
    for step in re.findall(r'<steps>(?:(?!<steps>).)*?</steps>', v, re.S):
        continue
        outer = re.sub(r'<customElement>.*?</customElement>', '', step, flags=re.S)
        print('  STEP', re.search(r'<label>([^<]+)</label>', outer).group(1), '| parent', (re.search(r'<parentStep>([^<]+)</parentStep>', outer) or [0, '-'])[1])
        for p in re.findall(r'<parameters>(.*?)</parameters>', step, re.S):
            n = re.search(r'<name>([^<]+)</name>', p).group(1); t = re.search(r'<type>([^<]+)</type>', p); val = re.search(r'<value>([^<]*)</value>', p)
            io = 'OUT' if '<output>true</output>' in p else 'in'
            print(f'     {io} {n} = {t and t.group(1)}:{val and val.group(1)}')
    for var in re.findall(r'<variables>(.*?)</variables>', v, re.S):
        n = re.search(r'<name>([^<]+)</name>', var); val = re.search(r'<value>([^<]*)</value>', var)
        if n and 'illing' in n.group(1).lower() or (n and 'frequency' in n.group(1).lower()):
            print('  VAR', n.group(1), '=', val and val.group(1), '|', ' '.join(re.findall(r'<(\w+)>([^<]{1,40})</\1>', var)[0:0]) , re.sub(r'\s+', ' ', var)[:260])
PY
echo "== schedules"
sf data query --query "SELECT Id, Name, IsActive, ScheduleType, AdjustmentMethod FROM PriceAdjustmentSchedule" --target-org target 2>&1 | tail -12
echo "== Billing_Frequency_Value__c on quote lines"
sf sobject describe --sobject QuoteLineItem --target-org target --json | jq -c '.result.fields[] | select(.name=="Billing_Frequency_Value__c") | {name, type, calculated, calculatedFormula}'
sf data query --query "SELECT Quote.QuoteNumber, Product2.ProductCode, BillingFrequency, Billing_Frequency_Value__c, SubscriptionTerm FROM QuoteLineItem WHERE Quote.QuoteNumber IN ('00000119','00000122','00000105') AND Product2.ProductCode = 'MB-ACC'" --target-org target 2>&1 | tail -6
