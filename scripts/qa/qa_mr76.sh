#!/usr/bin/env bash
# READ-ONLY QA for MR-76 MB-PRD-05 Hardware: EU qualification and Ship-To / Payments rules.
set -uo pipefail
q() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== hardware qualification rows"
q "SELECT Product.ProductCode, Region__c, IsQualified, EffectiveFromDate, EffectiveToDate FROM ProductQualification WHERE Product.ProductCode LIKE 'MB-HW-%' ORDER BY Product.ProductCode" | jq -r '.[] | "   \(.Product.ProductCode) | \(.Region__c) | qualified=\(.IsQualified) | \(.EffectiveFromDate) - \(.EffectiveToDate)"'
q "SELECT Product.ProductCode, FIELDS(STANDARD) FROM ProductDisqualification WHERE Product.ProductCode LIKE 'MB-HW-%'" 2>/dev/null | head -c 600; echo
q "SELECT ProductCategory.Name, FIELDS(STANDARD) FROM ProductCategoryQualification" | head -c 800; echo
q "SELECT ProductCategory.Name, FIELDS(STANDARD) FROM ProductCategoryDisqual" | head -c 800; echo
echo "== active qualification procedure and decision tables"
q "SELECT DeveloperName, Status, VersionNumber, LastModifiedDate FROM ExpressionSetDefinitionVersion WHERE DeveloperName LIKE '%Qualification%' ORDER BY LastModifiedDate DESC" "--use-tooling-api"
q "SELECT DeveloperName, Status, LastModifiedDate FROM DecisionTable WHERE DeveloperName LIKE '%Qualif%'"
echo "== hardware flows"
for f in Validate_Hardware_Ship_To_Address; do id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = '$f' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty'); echo "   $f active=$([ -n "$id" ] && echo yes || echo no)"; done
echo "== account regions in use"
q "SELECT Region__c r, COUNT(Id) n FROM Account GROUP BY Region__c"
