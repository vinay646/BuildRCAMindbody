#!/usr/bin/env bash
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
U=$(sf org display --target-org target --json | jq -r '.result.username'); UID=$(q "SELECT Id FROM User WHERE Username = '$U'" | jq -r '.[0].Id')
F=$(sf api request rest "$API/sobjects/PermissionSet/describe" --target-org target | jq -r '[.fields[] | select(.name|test("Promo|Coupon";"i")) | .name] | join(",")')
echo "PERMISSION FIELDS $F"
for f in ${F//,/ }; do echo "== sets with $f: $(q "SELECT Name, Label, IsOwnedByProfile, PermissionSetGroupId FROM PermissionSet WHERE $f = true LIMIT 20" | jq -c '[.[] | {Name, Label, IsOwnedByProfile}]')"; done
echo "USER ASSIGNMENTS $(q "SELECT PermissionSet.Name, PermissionSet.Label FROM PermissionSetAssignment WHERE AssigneeId = '$UID' AND (PermissionSet.Name LIKE '%romo%' OR PermissionSet.Label LIKE '%romo%' OR PermissionSet.Name LIKE '%Pricing%' OR PermissionSet.Name LIKE '%Revenue%')")"
echo "PSL $(q "SELECT PermissionSetLicense.MasterLabel, PermissionSetLicense.DeveloperName FROM PermissionSetLicenseAssign WHERE AssigneeId = '$UID'" | jq -c '[.[] | .PermissionSetLicense.MasterLabel]')"
