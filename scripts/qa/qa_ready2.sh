#!/usr/bin/env bash
# READ-ONLY follow-up: MR-74 Branded App quantity in bundles; MR-93 quote price book vs Region.
set -uo pipefail
API="/services/data/v$ORG_API"
raw() { sf data query --query "$1" --target-org target ${2:-} --json | jq -c 'if .status == 0 then [.result.records[]? | del(.attributes) | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== MR-74 BRANDED APP / ADD-ON COMPONENTS"
raw "SELECT ParentProduct.ProductCode, ChildProduct.ProductCode, Quantity, IsQuantityEditable, QuantityScaleMethod, MinQuantity, MaxQuantity, IsComponentRequired, IsDefaultComponent FROM ProductRelatedComponent WHERE ChildProduct.ProductCode IN ('MB-APP','MB-APP-SET','MB-F-AIC')"
echo "== MR-74 RECENT QUOTE LINES WITH BRANDED APP"
raw "SELECT Quote.QuoteNumber, Product2.ProductCode, Quantity, CreatedDate FROM QuoteLineItem WHERE Product2.ProductCode IN ('MB-APP','MB-APP-SET') ORDER BY CreatedDate DESC LIMIT 10"
echo "== MR-93 QUOTE PRICE BOOK EDITABLE"
sf api request rest "$API/sobjects/Quote/describe" --target-org target | jq -c '[.fields[] | select(.name=="Pricebook2Id" or .name=="CurrencyIsoCode") | {name, updateable, createable}]'
echo "== MR-93 UK PRICE BOOK ID"; raw "SELECT Id, Name FROM Pricebook2"
echo "== MR-93 QUOTES WHOSE PRICE BOOK DOES NOT MATCH REGION (created since 10 Nov)"
raw "SELECT QuoteNumber, Opportunity.Account.Region__c, Pricebook2.Name, CurrencyIsoCode, CreatedDate FROM Quote WHERE CreatedDate >= 2026-11-10T00:00:00Z ORDER BY CreatedDate DESC LIMIT 60" | jq -c '[.[] | select((.Opportunity.Account.Region__c=="UK" and .Pricebook2.Name!="United Kingdom") or (.Opportunity.Account.Region__c=="NA" and .Pricebook2.Name!="North America & Asia (USD)") or (.Opportunity.Account.Region__c=="AU" and .Pricebook2.Name!="Australia") or (.Opportunity.Account.Region__c=="EU" and .Pricebook2.Name!="Europe"))]'
echo "== MR-93 OPPORTUNITY PRICE BOOK FLOW (only on create?)"
id=$(sf data query --use-tooling-api --query "SELECT Id FROM Flow WHERE Definition.DeveloperName = 'Opportunity_Update_PriceBook_Currency_Based_on_Account_Field' AND Status = 'Active' LIMIT 1" --target-org target --json | jq -r '.result.records[0].Id // empty')
sf api request rest "$API/tooling/sobjects/Flow/$id" --target-org target | jq -c '.Metadata.start | {when: .recordTriggerType, filters: [.filters[]? | "\(.field) \(.operator)"]}'
