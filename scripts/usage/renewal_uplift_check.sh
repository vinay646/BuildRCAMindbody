#!/usr/bin/env bash
# CHANGES test data (MR103 Q2C04 account): renews its first Ultimate asset (5% uplift), reprices, checks net = base x 1.05
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
acc=$(q "SELECT Id FROM Account WHERE Name LIKE 'MR103 Q2C04%' LIMIT 1" '.result.records[0].Id' | tr -d '"')
a=$(q "SELECT Id FROM Asset WHERE AccountId = '$acc' AND Name = 'Ultimate' ORDER BY CreatedDate LIMIT 1" '.result.records[0].Id' | tr -d '"')
r=$(sf api request rest "$API/actions/standard/initiateRenewal" --method POST --body "{\"inputs\":[{\"renewAssetIds\":[\"$a\"],\"renewOutputType\":\"Quote\"}]}" --target-org target 2>&1 | jq -r '.[0].outputValues.renewRecordId // .[0].errors[0].message')
echo "renewal quote: $r"; sleep 30
px() { f=$(mktemp --suffix=.apex); printf "List<QuoteLineItem> ls = [SELECT Id FROM QuoteLineItem WHERE QuoteId = '%s'];\nfor (QuoteLineItem l : ls) l.UnitPriceUplift = %s;\nupdate ls;\nRepriceQuotesPST.reprice(new Set<String>{ '%s' });\n" "$r" "$1" "$r" > $f
  sf apex run --file $f --target-org target --json | jq -c '{success: .result.success, problem: (.result.exceptionMessage // .result.compileProblem)}' >&2
  q "SELECT NetUnitPrice FROM QuoteLineItem WHERE QuoteId = '$r' AND Product2.ProductCode = 'MB-ULT'" '.result.records[0].NetUnitPrice'; }
base=$(px 0); up=$(px 5)
echo "base (0% uplift): $base | with 5% uplift: $up"
python3 -c "
import sys; b=float('$base' or 0); u=float('$up' or 0)
ok=b>0 and abs(u-b*1.05)<=0.02
print('RENEWAL', 'PASS' if ok else 'FAIL', 'ratio', round(u/b,4) if b else None); sys.exit(0 if ok else 1)"
