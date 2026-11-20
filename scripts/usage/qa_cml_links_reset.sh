#!/usr/bin/env bash
# CHANGES the org: deletes the product links of the Mindbody Plans constraint model (so the CML can be saved again).
sid=$(sf data query --query "SELECT Id FROM ExpressionSet WHERE ApiName = 'Mindbody_Plans'" --target-org target --json | jq -r '.result.records[0].Id')
ids=$(sf data query --query "SELECT Id FROM ExpressionSetConstraintObj WHERE ExpressionSetId = '$sid'" --target-org target --json | jq -r '.result.records[].Id')
n=0; f=0
for id in $ids; do sf data delete record --sobject ExpressionSetConstraintObj --record-id $id --target-org target >/dev/null 2>&1 && n=$((n+1)) || f=$((f+1)); done
echo "model $sid: links deleted $n, failed $f, left $(sf data query --query "SELECT COUNT() FROM ExpressionSetConstraintObj WHERE ExpressionSetId = '$sid'" --target-org target --json | jq -r .result.totalSize)"
