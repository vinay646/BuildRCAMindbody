#!/usr/bin/env bash
# READ ONLY: QuoteLineItem / QuoteLineGroup triggers and their source
sf data query --use-tooling-api --query "SELECT Name, TableEnumOrId, Status FROM ApexTrigger WHERE TableEnumOrId IN ('QuoteLineItem','QuoteLineGroup','Quote')" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)]'
for t in $(sf data query --use-tooling-api --query "SELECT Name FROM ApexTrigger WHERE TableEnumOrId IN ('QuoteLineItem','QuoteLineGroup') AND Status='Active'" --target-org target --json | jq -r '.result.records[]?.Name'); do
  echo "######## $t"; sf data query --use-tooling-api --query "SELECT Body FROM ApexTrigger WHERE Name = '$t'" --target-org target --json | jq -r '.result.records[0].Body' | head -80
done
