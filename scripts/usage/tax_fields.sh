#!/usr/bin/env bash
# READ ONLY: tax treatment fields, legal entities, mock adapter
q() { sf data query --query "$1" --target-org target --json | jq -c "$2"; }
sf sobject describe --sobject TaxTreatment --target-org target --json | jq -c '[.result.fields[] | select(.createable) | "\(.name):\(.type)\(if .picklistValues|length>0 then "=" + ([.picklistValues[].value]|join("/")) else "" end)"]'
echo "US treatment: $(q "SELECT FIELDS(STANDARD) FROM TaxTreatment WHERE Name = 'Default Tax Policy'" '.result.records[0] | del(.attributes, .OwnerId, .CreatedById, .LastModifiedById, .SystemModstamp, .CreatedDate, .LastModifiedDate, .LastViewedDate, .LastReferencedDate, .IsDeleted)')"
echo "legal entities: $(q "SELECT Id, Name, LegalEntityCountry FROM LegalEntity" '[.result.records[] | "\(.Name)|\(.Id)|\(.LegalEntityCountry)"]')"
echo "products tax policy: $(q "SELECT TaxPolicy.Name, COUNT(Id) n FROM Product2 WHERE ProductCode LIKE 'MB-%' GROUP BY TaxPolicy.Name" '[.result.records[] | "\(.Name):\(.n)"]')"
echo "adapter class: $(sf data query --use-tooling-api --query "SELECT Name, LengthWithoutComments FROM ApexClass WHERE Name LIKE '%MockTax%'" --target-org target --json | jq -c '[.result.records[] | "\(.Name):\(.LengthWithoutComments)"]')"
