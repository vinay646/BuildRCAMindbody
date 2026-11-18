#!/usr/bin/env bash
# READ-ONLY: users named Bhavana / Vinay / admin, and the permission sets, groups and permission set licenses of each.
set -uo pipefail
raw() { sf data query --query "$1" --target-org target --json | jq -c 'if .status == 0 then [.result.records[]? | walk(if type == "object" then del(.attributes) else . end)] else {error: .message} end'; }
echo "== RUNNING AS: $(sf org display --target-org target --json | jq -r .result.username)"
echo "== CANDIDATE USERS"
raw "SELECT Id, Name, Username, Email, IsActive, Profile.Name, Profile.UserLicense.Name FROM User WHERE Name LIKE '%Bhavana%' OR Name LIKE '%Vinay%' OR Username LIKE 'admin@%' OR Email LIKE 'vinay%' OR Email LIKE 'bhavana%'" | jq -c '.[]'
for u in $(sf data query --query "SELECT Id FROM User WHERE Name LIKE '%Bhavana%' OR Name LIKE '%Vinay%' OR Username LIKE 'admin@%' OR Email LIKE 'vinay%' OR Email LIKE 'bhavana%'" --target-org target --json | jq -r '.result.records[].Id'); do
  echo "===== USER $u"
  echo "-- permission sets"; raw "SELECT PermissionSet.Name, PermissionSet.Label, PermissionSet.License.Name FROM PermissionSetAssignment WHERE AssigneeId = '$u' AND PermissionSet.IsOwnedByProfile = false AND PermissionSetGroupId = null ORDER BY PermissionSet.Label" | jq -c '[.[] | "\(.PermissionSet.Label) [\(.PermissionSet.Name)]\(if .PermissionSet.License then " needs: " + .PermissionSet.License.Name else "" end)"]'
  echo "-- permission set groups"; raw "SELECT PermissionSetGroup.DeveloperName, PermissionSetGroup.MasterLabel FROM PermissionSetAssignment WHERE AssigneeId = '$u' AND PermissionSetGroupId != null" | jq -c '[.[] | .PermissionSetGroup.MasterLabel]'
  echo "-- permission set licenses"; raw "SELECT PermissionSetLicense.DeveloperName, PermissionSetLicense.MasterLabel FROM PermissionSetLicenseAssign WHERE AssigneeId = '$u' ORDER BY PermissionSetLicense.MasterLabel" | jq -c '[.[] | .PermissionSetLicense.MasterLabel]'
done
echo "== PSL SEATS (used / total) for PSLs held by admin users"
raw "SELECT MasterLabel, DeveloperName, UsedLicenses, TotalLicenses FROM PermissionSetLicense WHERE Status = 'Active' ORDER BY MasterLabel" | jq -c '[.[] | "\(.MasterLabel): \(.UsedLicenses)/\(.TotalLicenses)"]'
