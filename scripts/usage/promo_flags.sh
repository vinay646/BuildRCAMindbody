#!/usr/bin/env bash
# Read-only: promotion settings related to coupons / automatic application, for LAUNCH3, SWITCH50, GROW2
sf sobject describe --sobject Promotion --target-org target --json 2>/dev/null | jq -c '[.result.fields[] | select(.name|test("Coupon|Auto|Applic|Eligib|Display|Optional|Manual|Type|Usage";"i")) | [.name, .type, ([.picklistValues[]?.value]|join("/"))]]' | sed 's/^/FIELDS /'
sf data query --query "SELECT FIELDS(ALL) FROM Promotion WHERE Name IN ('LAUNCH3','SWITCH50','GROW2') LIMIT 5" --target-org target --json 2>/dev/null | jq -c '.result.records[] | with_entries(select(.value != null and (.key|test("Created|LastMod|System|Owner|attributes|Viewed|Referenced|Description|^Id$")|not)))' | sed 's/^/PROMO /'
