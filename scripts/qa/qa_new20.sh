#!/usr/bin/env bash
# READ-ONLY QA (20 Nov): MR-77 fix, MR-99 list prices / price books, MR-114 UI review, org changes since 17 Nov.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "################ ORG CHANGES SINCE 17 NOV 09:00 UTC (setup audit trail)"
raw "SELECT CreatedDate, CreatedBy.Name, Section, Display FROM SetupAuditTrail WHERE CreatedDate >= 2026-11-17T09:00:00Z ORDER BY CreatedDate LIMIT 400" | jq -r '.[]? | "\(.CreatedDate[:16]) | \(.CreatedBy.Name) | \(.Section) | \(.Display)"' | cut -c1-230
echo; echo "################ MR-77 usage products billing policy"
raw "SELECT ProductCode, Name, BillingPolicy.Name, BillingPolicy.Status FROM Product2 WHERE ProductCode IN ('MB-PAY','MB-MKT','MB-SMS')"
raw "SELECT BillingPolicy.Name, Name, LegalEntity.Name, Status, BillingTreatment.Name FROM BillingTreatment WHERE BillingPolicy.Name LIKE '%Arrears%'" 2>/dev/null
raw "SELECT BillingPolicy.Name, Name, LegalEntity.Name, Status FROM BillingTreatment WHERE BillingPolicy.Name LIKE '%Arrears%'"
raw "SELECT Name, Status, DefaultBillingTreatment.Name, BillingTreatmentSelection FROM BillingPolicy"
echo "   usage resources: $(raw "SELECT Product.ProductCode, UsageResource.Name FROM ProductUsageResource WHERE Product.ProductCode IN ('MB-PAY','MB-MKT','MB-SMS')" | head -c 400)"
echo; echo "################ MR-99 price books"
raw "SELECT Id, Name, IsActive, IsStandard FROM Pricebook2"
echo "== plan / add-on / service list prices by book and currency (Monthly selling models)"
raw "SELECT Product2.ProductCode, Pricebook2.Name, CurrencyIsoCode, ProductSellingModel.Name, UnitPrice, IsActive FROM PricebookEntry WHERE Product2.ProductCode LIKE 'MB-%' AND Pricebook2.IsStandard = false AND IsActive = true ORDER BY Product2.ProductCode, Pricebook2.Name, ProductSellingModel.Name LIMIT 2000" | jq -r '.[] | "\(.Product2.ProductCode)|\(.Pricebook2.Name)|\(.CurrencyIsoCode)|\(.ProductSellingModel.Name // "-")|\(.UnitPrice)"' > pbe.txt
wc -l pbe.txt; cat pbe.txt
echo "== products with no entry in some regional book"
raw "SELECT ProductCode, Name, IsActive FROM Product2 WHERE ProductCode LIKE 'MB-%' AND IsActive = true ORDER BY ProductCode" | jq -r '.[] | .ProductCode' > prods.txt
for b in $(raw "SELECT Name FROM Pricebook2 WHERE IsStandard = false AND IsActive = true" | jq -r '.[].Name | @base64'); do
  name=$(echo $b | base64 -d); miss=$(for p in $(cat prods.txt); do grep -q "^$p|$name|" pbe.txt || echo -n "$p "; done); echo "   $name missing: ${miss:-none}"
done
echo "== MB-APP / MB-TAM catalog placement and selling flags"
raw "SELECT ProductCode, Name, IsActive, IsSoldOnlyWithOtherProds, Type, QuantityUnitOfMeasure FROM Product2 WHERE ProductCode IN ('MB-APP','MB-TAM','MB-STR','MB-ACC','MB-ULT')"
raw "SELECT Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name FROM ProductCategoryProduct WHERE Product.ProductCode IN ('MB-APP','MB-TAM','MB-STR','MB-ACC','MB-ULT')"
echo "== catalogs and categories (product counts)"
raw "SELECT Id, Name, CatalogType, EffectiveStartDate, EffectiveEndDate FROM ProductCatalog"
raw "SELECT Catalog.Name, Name, IsNavigational, NumberOfProducts, ParentCategory.Name FROM ProductCategory ORDER BY Catalog.Name, SortOrder"
echo "== recent quotes for T06 UK / Starter x3 (Shaik)"
raw "SELECT QuoteNumber, Name, Opportunity.Account.Name, Opportunity.Account.Region__c, Pricebook2.Name, CurrencyIsoCode, LegalEntity.Name, CreatedDate, CreatedBy.Name FROM Quote WHERE CreatedDate >= 2026-11-18T00:00:00Z ORDER BY CreatedDate DESC LIMIT 10"
raw "SELECT Quote.QuoteNumber, Product2.ProductCode, Quantity, BillingFrequency, ListPrice, UnitPrice, NetUnitPrice, TotalPrice, CreatedDate FROM QuoteLineItem WHERE CreatedDate >= 2026-11-18T00:00:00Z ORDER BY CreatedDate DESC LIMIT 20"
echo "== volume tiers on Starter (why 5% at 3 locations?)"
raw "SELECT PriceAdjustmentSchedule.Name, Product2.ProductCode, LowerBound, UpperBound, TierType, TierValue, CurrencyIsoCode FROM PriceAdjustmentTier WHERE Product2.ProductCode = 'MB-STR' AND CurrencyIsoCode = 'USD' ORDER BY PriceAdjustmentSchedule.Name, LowerBound LIMIT 40"
echo "== staff-related pricing inputs (PRC-03: price must not depend on staff)"
for o in Account Quote QuoteLineItem; do echo "   $o staff fields: $(sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -c '[.fields[] | select(.name|test("staff|user_count|users__c";"i")) | .name]')"; done
echo; echo "################ MR-114 UI review"
for o in Account Contact Opportunity Quote; do
  echo "== $o custom fields: label | help text"
  sf api request rest "$API/sobjects/$o/describe" --target-org target | jq -r '.fields[] | select(.custom) | "\(.name) | \(.label) | \(if (.inlineHelpText // "") == "" then "NO HELP TEXT" else "help: " + (.inlineHelpText|.[0:60]) end)"'
done
echo "== record pages (FlexiPage) for these objects"
sf data query --use-tooling-api --query "SELECT DeveloperName, MasterLabel, EntityDefinitionId, Type, LastModifiedDate, LastModifiedBy.Name FROM FlexiPage WHERE Type = 'RecordPage' ORDER BY LastModifiedDate DESC LIMIT 40" --target-org target --json | jq -r '.result.records[]? | "\(.DeveloperName) | \(.EntityDefinitionId) | \(.LastModifiedDate[:16]) | \(.LastModifiedBy.Name)"'
echo "== page assignments (org default / app) from object metadata"
rm -rf ui && mkdir ui && sf project retrieve start --metadata "CustomObject:Account" --metadata "CustomObject:Contact" --metadata "CustomObject:Opportunity" --metadata "CustomObject:Quote" --target-org target --target-metadata-dir ui --unzip --wait 10 >/dev/null 2>&1
for f in $(find ui -name '*.object'); do echo "-- $(basename $f)"; python3 - "$f" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
for m in re.findall(r"<actionOverrides>(.*?)</actionOverrides>", s, re.S):
    if "<actionName>View</actionName>" in m and "<content>" in m:
        g=lambda t: (re.search(f"<{t}>(.*?)</{t}>", m) or [None,""])[1]
        print("   View override:", g("content"), "| form factor", g("formFactor"), "| type", g("type"), "| profile/app", g("pageOrSobjectType"), g("skipRecordTypeSelect"))
PY
done
echo "== app-level page assignments (profileActionOverrides in apps)"
rm -rf apps && mkdir apps && sf project retrieve start --metadata "CustomApplication" --target-org target --target-metadata-dir apps --unzip --wait 10 >/dev/null 2>&1
grep -l -E "<content>[^<]*(Account|Opportunity|Quote|Contact)[^<]*</content>" $(find apps -name '*.app') 2>/dev/null | while read f; do echo "-- $(basename $f)"; grep -o "<content>[^<]*</content>\|<pageOrSobjectType>[^<]*</pageOrSobjectType>" $f | paste - - | grep -E "Account|Opportunity|Quote|Contact" | head -8; done
echo "== record page sections (field section labels) per page"
rm -rf fp && mkdir fp && for p in $(sf data query --use-tooling-api --query "SELECT DeveloperName FROM FlexiPage WHERE Type = 'RecordPage' AND (EntityDefinitionId IN ('Account','Opportunity','Quote','Contact'))" --target-org target --json | jq -r '.result.records[].DeveloperName'); do
  sf project retrieve start --metadata "FlexiPage:$p" --target-org target --target-metadata-dir fp --unzip --wait 10 >/dev/null 2>&1
done
for f in $(find fp -name '*.flexipage'); do echo "-- $(basename $f .flexipage): $(grep -A1 '<name>label</name>' $f | grep -o '<value>[^<]*</value>' | sed 's/<[^>]*>//g' | tr '\n' ';' | cut -c1-600)"; done
