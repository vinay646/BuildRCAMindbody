#!/usr/bin/env bash
# CHANGES test data (MR103 Q2C04 account): renews its first Ultimate asset (5% uplift), reprices, checks net = base x 1.05
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
acc=$(q "SELECT Id FROM Account WHERE Name LIKE 'MR103 Q2C04%' LIMIT 1" '.result.records[0].Id' | tr -d '"')
a=$(q "SELECT Id FROM Asset WHERE AccountId = '$acc' AND Name = 'Ultimate' ORDER BY CreatedDate LIMIT 1" '.result.records[0].Id' | tr -d '"')
r=$(sf api request rest "$API/actions/standard/initiateRenewal" --method POST --body "{\"inputs\":[{\"renewAssetIds\":[\"$a\"],\"renewOutputType\":\"Quote\"}]}" --target-org target 2>&1 | jq -r '.[0].outputValues.renewRecordId // .[0].errors[0].message')
echo "renewal quote: $r"; sleep 30
f=$(mktemp --suffix=.apex); cat > $f <<APEX
List<QuoteLineItem> ls = [SELECT Id FROM QuoteLineItem WHERE QuoteId = '$r'];
for (QuoteLineItem l : ls) { if (l.UnitPriceUplift == null) l.UnitPriceUplift = 5; }
update ls;
RepriceQuotesPST.reprice(new Set<String>{ '$r' });
APEX
sed -i "s/if (l.UnitPriceUplift == null) l.UnitPriceUplift = 5;/l.UnitPriceUplift = 5;/" $f
sf apex run --file $f --target-org target --json | jq -c '{success: .result.success, problem: (.result.exceptionMessage // .result.compileProblem)}'
l=$(q "SELECT ListPrice, NetUnitPrice, UnitPriceUplift, ApplUnitPriceUpliftPct FROM QuoteLineItem WHERE QuoteId = '$r' AND Product2.ProductCode = 'MB-ULT'" '.result.records[0] | del(.attributes)')
echo "line: $l"
python3 -c "
import json,sys; l=json.loads('$l'); n=float(l['NetUnitPrice'] or 0)
ok=abs(n-449.1*1.05)<=0.02
print('RENEWAL', 'PASS' if ok else 'FAIL', 'net', n, 'want', round(449.1*1.05,2)); sys.exit(0 if ok else 1)"
