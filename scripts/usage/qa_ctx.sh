#!/usr/bin/env bash
# READ ONLY: context attributes + fields the Mindbody Plans model reads, and bundle component Ids.
for o in Quote Opportunity Account; do
  echo "== $o MB fields: $(sf sobject describe --sobject $o --target-org target --json | jq -r '[.result.fields[] | select(.name|test("MB_|Hierarchy|Location|Prior";"i")) | .name] | join(",")')"
done
mkdir -p /tmp/ctx && cd /tmp/ctx && sf project generate --name c >/dev/null 2>&1; cd c
sf project retrieve start --metadata "ContextDefinition:RLM_SalesTransactionContext" --target-org target >/dev/null 2>&1
f=$(find . -name "RLM_SalesTransactionContext*.xml" | head -1); echo "== context file: $f ($(wc -c < "$f" 2>/dev/null) bytes)"
echo "== Mb attributes: $(grep -o '<title>Mb[A-Za-z]*</title>' "$f" | sort -u | sed 's/<[^>]*>//g' | tr '\n' ' ')"
grep -n -B4 "<contextAttribute>MbHierarchyLocationCount\|<contextAttribute>MbPriorSystem" "$f" | grep -E "objectName|queryAttribute|contextAttribute>" 
echo "== active context version: $(grep -c '<isActive>true' "$f")"
echo "== COMPONENT IDS"
sf data query --query "SELECT Id, ParentProduct.ProductCode, ChildProduct.ProductCode FROM ProductRelatedComponent WHERE ParentProduct.ProductCode LIKE 'MB-%'" --target-org target --json | jq -r '.result.records[] | "\(.ParentProduct.ProductCode)|\(.ChildProduct.ProductCode)|\(.Id)"'
echo "== PRODUCT IDS"
sf data query --query "SELECT Id, ProductCode, Name FROM Product2 WHERE ProductCode LIKE 'MB-%'" --target-org target --json | jq -r '.result.records[] | "\(.ProductCode)|\(.Id)|\(.Name)"'
