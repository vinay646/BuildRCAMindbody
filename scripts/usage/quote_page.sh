#!/usr/bin/env bash
# Read-only: Quote record pages in the org and the components on each (which page is default)
t() { sf data query --use-tooling-api --query "$1" --target-org target --json 2>/dev/null; }
for id in $(t "SELECT Id FROM FlexiPage WHERE EntityDefinitionId = 'Quote'" | jq -r '.result.records[].Id'); do
  t "SELECT DeveloperName, LastModifiedDate, Metadata FROM FlexiPage WHERE Id = '$id'" | jq -r '.result.records[0] | "\(.DeveloperName) (\(.LastModifiedDate[0:10])): " + ([.Metadata.flexiPageRegions[]?.itemInstances[]?.componentInstance.componentName // empty] | unique | map(select(test("runtime|rca|revenue|transaction";"i"))) | join(", "))'
done
echo "DEFAULT: $(t "SELECT FlexiPage.DeveloperName FROM FlexiPage WHERE EntityDefinitionId = 'Quote'" >/dev/null; sf data query --use-tooling-api --query "SELECT DeveloperName FROM FlexiPage WHERE EntityDefinitionId = 'Quote' AND Type = 'RecordPage'" --target-org target --json | jq -c '[.result.records[].DeveloperName]')"
