#!/usr/bin/env bash
# READ ONLY: QA quote term / shipping fields, required Account fields
sf sobject describe --sobject Quote --target-org target --json | jq -r '[.result.fields[] | select(.name|test("term|Term|Shipping";"")) | "\(.name):\(.type)"] | join(" ")'
sf sobject describe --sobject Account --target-org target --json | jq -r '[.result.fields[] | select(.nillable==false and .createable==true and .defaultedOnCreate==false) | .name] | join(" ")'
sf data create record --sobject Account --values "Name='CML TEST account'" --target-org target --json 2>&1 | jq -c '{status, message, id: .result.id}'
