#!/usr/bin/env bash
# READ-ONLY: Ids of the Mindbody core plan products.
sf data query --query "SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT')" --target-org target --json | jq -r '.result.records[] | "\(.ProductCode)=\(.Id)"'
