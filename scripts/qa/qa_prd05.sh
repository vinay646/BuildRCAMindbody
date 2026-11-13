#!/usr/bin/env bash
# READ-ONLY QA for MB-PRD-05 Hardware: MB-HW-RDR, MB-HW-TRM, MB-HW-DOOR.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes) | with_entries(select(.value != null and (.key|test("^(IsDeleted|SystemModstamp|LastViewedDate|LastReferencedDate|LastModifiedById|CreatedById|OwnerId|CreatedDate|LastModifiedDate)$")|not)))] else {error: .message} end'; }
H="('MB-HW-RDR','MB-HW-TRM','MB-HW-DOOR')"
echo "== PRODUCTS"; raw "SELECT ProductCode, Name, IsActive, Family, IsSoldOnlyWithOtherProds, QuantityUnitOfMeasure, UnitOfMeasure.Name FROM Product2 WHERE ProductCode IN $H"
echo "== SELLING MODELS"; raw "SELECT Product2.ProductCode, ProductSellingModel.Name, ProductSellingModel.SellingModelType FROM ProductSellingModelOption WHERE Product2.ProductCode IN $H"
echo "== PRICES"; raw "SELECT Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode, UnitPrice, ProductSellingModel.Name, IsActive FROM PricebookEntry WHERE Product2.ProductCode IN $H ORDER BY Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode"
echo "== VALIDATION RULES (all quote objects)"; raw "SELECT EntityDefinition.QualifiedApiName, ValidationName, Active, ErrorMessage FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Quote','QuoteLineItem','QuoteLineGroup','Order','OrderItem','Opportunity','OpportunityLineItem')" "--use-tooling-api"
echo "== VALIDATION RULES (any object, by message)"; raw "SELECT EntityDefinition.QualifiedApiName, ValidationName, Active, ErrorMessage FROM ValidationRule WHERE ErrorMessage LIKE '%ardware%' OR ErrorMessage LIKE '%Ship%' OR ErrorMessage LIKE '%Payment%' OR ErrorMessage LIKE '%term%' OR ErrorMessage LIKE '%Technical%'" "--use-tooling-api"
echo "== FLOWS ON QUOTE OBJECTS"; raw "SELECT ApiName, Label, ProcessType, TriggerType, TriggerObjectOrEventLabel FROM FlowDefinitionView WHERE IsActive = true AND (TriggerObjectOrEventLabel LIKE '%Quote%' OR Label LIKE '%Hardware%' OR Label LIKE '%Payment%' OR Label LIKE '%Ship%' OR Label LIKE '%Term%')"
echo "== APEX TRIGGERS"; raw "SELECT Name, TableEnumOrId, Status FROM ApexTrigger WHERE NamespacePrefix = null" "--use-tooling-api"
echo "== PRODUCT QUALIFICATION RULES"; raw "SELECT FIELDS(ALL) FROM ProductQualification LIMIT 50"
raw "SELECT FIELDS(ALL) FROM ProductDisqualification LIMIT 50"
echo "== QUALIFICATION PROCEDURES"; raw "SELECT Id, DeveloperName, Status, VersionNumber FROM ExpressionSetDefinitionVersion WHERE DeveloperName LIKE '%Qualif%'" "--use-tooling-api"
echo "== DECISION TABLES"; raw "SELECT Id, DeveloperName, MasterLabel, Status, SourceObject FROM DecisionTable" "--use-tooling-api"
echo "== CML hardware / payments lines"
for id in $(sf data query --use-tooling-api --query "SELECT Id FROM ExpressionSetDefinitionVersion WHERE (DeveloperName LIKE '%Mindbody%' OR DeveloperName LIKE 'MB%' OR DeveloperName LIKE '%Tier%' OR DeveloperName LIKE '%Hardware%')" --target-org target --json | jq -r '.result.records[]?.Id'); do
  sf api request rest "$API/tooling/sobjects/ExpressionSetDefinitionVersion/$id/ConstraintModel" --target-org target > cml.txt 2>&1 || true
  echo "-- $id size $(wc -c < cml.txt)"; grep -n -i -E "HW|hardware|payment|reader|terminal|door|ship|require|message|region" cml.txt | head -30
done
