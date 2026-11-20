#!/usr/bin/env bash
# READ ONLY: what the Mindbody Plans constraint model needs in this org.
codes="'MB-ACC','MB-AIC','MB-APP','MB-APP-SET','MB-DCV','MB-ENT','MB-F-AIC','MB-F-APPL','MB-F-BM','MB-F-CDB','MB-F-LEAD','MB-F-MKTG','MB-F-PAS','MB-F-POS','MB-F-PROMO','MB-F-REP','MB-F-RES','MB-F-WEB','MB-HW-DOOR','MB-HW-RDR','MB-HW-TRM','MB-MKT','MB-PAY','MB-SMS','MB-STR','MB-TAM','MB-ULT'"
found=$(sf data query --query "SELECT ProductCode FROM Product2 WHERE ProductCode IN ($codes)" --target-org target --json | jq -r '[.result.records[].ProductCode] | sort | join(",")')
echo "products found ($(echo "$found" | tr ',' '\n' | grep -c .) of 27): $found"
echo "bundle component links (ProductRelatedComponent on MB- bundles): $(sf data query --query "SELECT COUNT() FROM ProductRelatedComponent WHERE ParentProduct.ProductCode LIKE 'MB-%'" --target-org target --json | jq -r .result.totalSize)"
echo "context definitions: $(sf data query --query "SELECT DeveloperName FROM ContextDefinition WHERE DeveloperName LIKE 'RLM_Sales%'" --target-org target --json 2>/dev/null | jq -r '[.result.records[]?.DeveloperName] | join(",")')"
echo "constraint models: $(sf data query --query "SELECT Name, ApiName FROM ExpressionSet WHERE InterfaceSourceType = 'Constraint'" --target-org target --json | jq -c '[.result.records[]? | {Name, ApiName}]')"
echo "loader class: $(sf data query --use-tooling-api --query "SELECT Name FROM ApexClass WHERE Name = 'MindbodyBuildLoader'" --target-org target --json | jq -r '.result.totalSize')"
echo "MB_Build_Data static resource: $(sf data query --use-tooling-api --query "SELECT Name, LastModifiedDate FROM StaticResource WHERE Name = 'MB_Build_Data'" --target-org target --json | jq -c '.result.records[0] | {Name, LastModifiedDate}')"
