#!/usr/bin/env bash
# CREATES test data in dev: Parent-Pay location under a Self-Pay parent; quote with the parent's contact as bill-to; order activated; shows which account the billing schedules and assets land on
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | del(.attributes)]'; }
mk() { sf api request rest "$API/sobjects/$1" --method POST --header "Sforce-Duplicate-Rule-Header: allowSave=true" --body "$2" --target-org target 2>&1 | tee mk.json | jq -r '.id // empty'; }
S=$(date -u +%m%d%H%M); D=$(date -u +%Y-%m-%d); E=$(date -u -d '+1 year -1 day' +%Y-%m-%d)
addr() { jq -nc --arg st "$1" '{BillingStreet:$st, BillingCity:"Austin", BillingState:"Texas", BillingPostalCode:"73301", BillingCountry:"United States", ShippingStreet:$st, ShippingCity:"Austin", ShippingState:"Texas", ShippingPostalCode:"73301", ShippingCountry:"United States"}'; }
PAR=$(mk Account "$(jq -nc --arg n "MBPayer Parent $S" --argjson a "$(addr "1$S Main St")" '$a + {Name:$n, CurrencyIsoCode:"USD", Account_Level__c:"Corporate", Payer_Type__c:"Self-Pay"}')")
[ -z "$PAR" ] && { echo "parent error $(head -c 400 mk.json)"; exit 1; }
CH=$(mk Account "$(jq -nc --arg n "MBPayer Location $S" --arg p "$PAR" --argjson a "$(addr "2$S Main St")" '$a + {Name:$n, CurrencyIsoCode:"USD", Account_Level__c:"Location", Payer_Type__c:"Parent-Pay", ParentId:$p}')")
[ -z "$CH" ] && { echo "child error $(head -c 400 mk.json)"; exit 1; }
PC=$(mk Contact "$(jq -nc --arg a "$PAR" --arg s "$S" '{FirstName:"Payer", LastName:("Billing" + $s), Email:("payer" + $s + "@example.org"), AccountId:$a}')")
CC=$(mk Contact "$(jq -nc --arg a "$CH" --arg s "$S" '{FirstName:"Loc", LastName:("Manager" + $s), Email:("loc" + $s + "@example.org"), AccountId:$a}')")
sleep 5; echo "child resolved payer: $(q "SELECT Resolved_Payer__r.Name FROM Account WHERE Id = '$CH'" | jq -r '.[0].Resolved_Payer__r.Name // "none"')"
PB=$(q "SELECT Pricebook2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ACC' AND CurrencyIsoCode = 'USD' AND IsActive = true AND Pricebook2.Name LIKE 'North America%' LIMIT 1" | jq -r '.[0].Pricebook2Id')
PBE=$(q "SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = 'MB-ACC' AND Pricebook2Id = '$PB' AND CurrencyIsoCode = 'USD' AND IsActive = true AND ProductSellingModel.Name = 'Term Monthly' LIMIT 1" | jq -c '.[0]')
LE=$(q "SELECT Id FROM LegalEntity WHERE Name = 'Default Legal Entity - US'" | jq -r '.[0].Id'); BT=$(q "SELECT Id FROM BillingTreatment WHERE Name = 'Mindbody - US - Advance'" | jq -r '.[0].Id')
OPP=$(sf data create record --sobject Opportunity --values "Name='MBPayer $S' AccountId=$CH StageName=Prospecting CloseDate=$D Pricebook2Id=$PB CurrencyIsoCode=USD" --target-org target --json | jq -r '.result.id')
BODY=$(jq -nc --arg opp "$OPP" --arg pb "$PB" --arg con "$PC" --arg d "$D" --arg e "$E" --arg le "$LE" --arg bt "$BT" --argjson p "$PBE" '{pricingPref:"System", catalogRatesPref:"Skip", configurationPref:{configurationMethod:"Skip"}, taxPref:"Skip", graph:{graphId:"g", records:[
 {referenceId:"q1", record:{attributes:{type:"Quote", method:"POST"}, Name:"MBPayer test", OpportunityId:$opp, Pricebook2Id:$pb, BillToContactId:$con, LegalEntityId:$le, StartDate:$d, RLM_TermMonths__c:12}},
 {referenceId:"l1", record:{attributes:{type:"QuoteLineItem", method:"POST"}, QuoteId:"@{q1.id}", Product2Id:$p.Product2Id, PricebookEntryId:$p.Id, Quantity:1, StartDate:$d, EndDate:$e, BillingFrequency:"Monthly", PeriodBoundary:"Anniversary", LegalEntityId:$le, BillingTreatmentId:$bt}}]}}')
echo "place: $(sf api request rest "$API/connect/rev/sales-transaction/actions/place" --method POST --body "$BODY" --target-org target 2>&1 | jq -c '{isSuccess, errorResponse}' 2>/dev/null)"
QT=$(q "SELECT Id FROM Quote WHERE OpportunityId = '$OPP'" | jq -r '.[0].Id'); sleep 8
echo "order: $(sf api request rest "$API/actions/standard/createOrderFromQuote" --method POST --body "{\"inputs\":[{\"quoteRecordId\":\"$QT\"}]}" --target-org target 2>&1 | jq -c '.[0] | {isSuccess, errors}')"
sleep 15; OID=$(q "SELECT Id FROM Order WHERE OpportunityId = '$OPP' OR QuoteId = '$QT' LIMIT 1" | jq -r '.[0].Id')
for _ in 1 2 3 4 5 6 7 8; do sleep 15; [ "$(q "SELECT Status FROM Order WHERE Id = '$OID'" | jq -r '.[0].Status')" = "Activated" ] && break; done
echo "ORDER $(q "SELECT OrderNumber, Status, Account.Name, BillToContact.Name, BillToContact.Account.Name, MB_Activation_Error__c FROM Order WHERE Id = '$OID'" | jq -c '.[0] | {n: .OrderNumber, s: .Status, acct: .Account.Name, billTo: .BillToContact.Name, billToAcct: .BillToContact.Account.Name, err: .MB_Activation_Error__c}')"
sleep 30
echo "BILLING SCHEDULES $(q "SELECT BillingAccount.Name, Status FROM BillingSchedule WHERE ReferenceEntityId = '$OID'" | jq -c '[.[] | [.BillingAccount.Name, .Status]]')"
echo "ASSETS $(q "SELECT Name, Account.Name FROM Asset WHERE Id IN (SELECT AssetId FROM OrderItem WHERE OrderId = '$OID')" 2>&1 | jq -c '[.[] | [.Name, .Account.Name]]' 2>/dev/null) / by account $(q "SELECT Name FROM Asset WHERE AccountId = '$CH'" | jq -c '[.[].Name]')"
echo "IDS parent=$PAR child=$CH order=$OID"
