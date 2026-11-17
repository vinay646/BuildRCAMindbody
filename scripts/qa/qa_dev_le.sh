#!/usr/bin/env bash
# READ-ONLY (ExploremoreRCA): legal entity setup gaps for MR-115.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes)] else {error: .message} end'; }
echo "== ORG $(sf org display --target-org target --json | jq -r .result.username)"
echo "== LEGAL ENTITIES"; raw "SELECT Id, Name, Status, LegalEntityCountry FROM LegalEntity"
echo "== BILLING TREATMENTS"; raw "SELECT Name, Status, BillingPolicy.Name, LegalEntity.Name FROM BillingTreatment ORDER BY LegalEntity.Name"
echo "== ACCOUNTING PERIODS"; raw "SELECT LegalEntity.Name, Name, StartDate, EndDate, Status FROM LegalEntyAccountingPeriod ORDER BY StartDate DESC LIMIT 20"
raw "SELECT LegalEntity.Name, COUNT(Id) n FROM LegalEntyAccountingPeriod GROUP BY LegalEntity.Name"
echo "== TAX"; raw "SELECT Name, Status, LegalEntity.Name, TaxPolicy.Name, TaxEngine.TaxEngineName FROM TaxTreatment"
echo "== ACCOUNT REGION/LE"; raw "SELECT MB_Region__c r, MB_Legal_Entity__r.Name le, COUNT(Id) n FROM Account GROUP BY MB_Region__c, MB_Legal_Entity__r.Name"
echo "== QUOTES WITH LE"; raw "SELECT LegalEntity.Name le, CurrencyIsoCode cur, COUNT(Id) n FROM Quote GROUP BY LegalEntity.Name, CurrencyIsoCode"
echo "== QLI WITH LE"; raw "SELECT LegalEntity.Name le, CurrencyIsoCode cur, COUNT(Id) n FROM QuoteLineItem GROUP BY LegalEntity.Name, CurrencyIsoCode"
echo "== OPP FIELD"; sf api request rest "$API/sobjects/Opportunity/describe" --target-org target | jq -c '[.fields[] | select(.name=="MB_Legal_Entity__c") | {type, calculatedFormula, referenceTo}]'
echo "== VALIDATION RULES"; raw "SELECT EntityDefinition.QualifiedApiName, ValidationName, Active, ErrorMessage FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ('Quote','QuoteLineItem','Opportunity','Account')" "--use-tooling-api"
echo "== FLS ACCOUNT LE"; raw "SELECT Parent.Label, Parent.Profile.Name, PermissionsEdit FROM FieldPermissions WHERE Field = 'Account.MB_Legal_Entity__c'"
echo "== CONTEXT LE"; grep -n -i "legalentity" force-app/main/default/contextDefinitions/RLM_SalesTransactionContext.contextDefinition-meta.xml | head -10
