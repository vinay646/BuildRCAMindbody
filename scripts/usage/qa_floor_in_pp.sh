#!/usr/bin/env bash
# READ ONLY: does any pricing procedure version in this org have a floor price step or the floor price book?
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
book=$(sf data query --query "SELECT Id FROM Pricebook2 WHERE Name = 'Mindbody Floor Prices'" --target-org target --json | jq -r '.result.records[0].Id // "none"')
sf project retrieve start --metadata "ExpressionSetDefinition:RLM_DefaultPricingProcedure" --target-org target >/dev/null 2>&1
f=$(find . -name "RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml")
python3 - "$f" "$book" <<'PY'
import sys, re
s = open(sys.argv[1]).read(); book = sys.argv[2][:15]
for v in re.findall(r'<versions>.*?</versions>', s, re.S):
    fn = re.search(r'<fullName>([^<]+)</fullName>', v).group(1); st = re.search(r'<status>(\w+)</status>', v).group(1)
    steps = [re.search(r'<label>([^<]+)</label>', re.sub(r'<customElement>.*?</customElement>', '', x, flags=re.S)).group(1)
             for x in re.findall(r'<steps>(?:(?!<steps>).)*?</steps>', v, re.S) if re.search(r'[Ff]loor', x) or (book != 'none' and book in x)]
    print(fn.split('_')[-1], st, '| floor steps:', steps or 'none')
PY
