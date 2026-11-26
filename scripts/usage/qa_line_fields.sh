#!/usr/bin/env bash
# Read-only: how the QA quote-line fields used by the pricing procedure get their values (formula / plain field) and which flows write them
sf sobject describe --sobject QuoteLineItem --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.name|test("Billing_Frequency_Value__c|Location_count__c|Locationcount__c")) | {name, type, calculated, formula: .calculatedFormula, default: .defaultValueFormula}]'
t() { sf data query --use-tooling-api --query "$1" --target-org target --json 2>/dev/null; }
for id in $(sf data query --query "SELECT ActiveVersionId FROM FlowDefinitionView WHERE IsActive = true AND ProcessType = 'AutoLaunchedFlow'" --target-org target --json 2>/dev/null | jq -r '.result.records[].ActiveVersionId'); do
  t "SELECT Definition.DeveloperName, Metadata FROM Flow WHERE Id = '$id'" | jq -r '.result.records[0] | select((.Metadata|tostring)|test("Billing_Frequency_Value__c|Location_count__c")) | "WRITER: \(.Definition.DeveloperName) on \(.Metadata.start.object) \(.Metadata.start.triggerType) \(.Metadata.start.recordTriggerType)"'
done
echo "CONTEXT MAP: $(sf data query --use-tooling-api --query "SELECT DeveloperName FROM ContextDefinition" --target-org target --json 2>/dev/null | jq -c '[.result.records[]?.DeveloperName]')"
