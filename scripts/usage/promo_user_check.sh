#!/usr/bin/env bash
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
echo "PROMO PERMISSION FIELDS $(sf api request rest "$API/sobjects/PermissionSet/describe" --target-org target | jq -c '[.fields[] | select(.name|test("Promo|Coupon|Apply";"i")) | .name]')"
echo "PROMO SET ASSIGNMENTS $(q "SELECT Assignee.Username, Assignee.Name, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN ('PromotionViewer','PromotionDesignerBasic')" | jq -c '[.[] | {u: .Assignee.Username, ps: .PermissionSet.Name}]')"
echo "PROMO PSL ASSIGNMENTS $(q "SELECT Assignee.Username, PermissionSetLicense.MasterLabel FROM PermissionSetLicenseAssign WHERE PermissionSetLicense.MasterLabel LIKE '%romo%'" | jq -c '[.[] | {u: .Assignee.Username, psl: .PermissionSetLicense.MasterLabel}]')"
echo "ALL PSLs $(q "SELECT MasterLabel, TotalLicenses, UsedLicenses, Status FROM PermissionSetLicense WHERE MasterLabel LIKE '%romo%' OR MasterLabel LIKE '%Loyal%' OR MasterLabel LIKE '%Revenue%' OR MasterLabel LIKE '%Pricing%'" | jq -c '[.[] | {MasterLabel, TotalLicenses, UsedLicenses, Status}]')"
echo "PROMO SETS $(q "SELECT Name, Label, LicenseId, License.Name FROM PermissionSet WHERE Name LIKE '%romo%'")"
