#!/usr/bin/env bash
# READ ONLY: who holds the full permission set licenses, and which licenses the RLM_RCB / RLM_RMI groups need.
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]?]'; }
echo "== LICENSE SEATS"
q "SELECT MasterLabel, TotalLicenses, UsedLicenses FROM PermissionSetLicense WHERE MasterLabel IN ('Agentforce (Default)','CG Analytics Apps','CRM Analytics Plus','Data Pipelines Base User','Salesforce Contracts Analytics App')" | jq -r '.[] | "  \(.MasterLabel): \(.UsedLicenses)/\(.TotalLicenses)"'
echo "== HOLDERS (license | user | username | active | last login | profile)"
q "SELECT PermissionSetLicense.MasterLabel, Assignee.Name, Assignee.Username, Assignee.IsActive, Assignee.LastLoginDate, Assignee.Profile.Name FROM PermissionSetLicenseAssign WHERE PermissionSetLicense.MasterLabel IN ('Agentforce (Default)','CG Analytics Apps','CRM Analytics Plus','Data Pipelines Base User','Salesforce Contracts Analytics App') ORDER BY PermissionSetLicense.MasterLabel, Assignee.Name" | jq -r '.[] | "  \(.PermissionSetLicense.MasterLabel) | \(.Assignee.Name) | \(.Assignee.Username) | \(.Assignee.IsActive) | \(.Assignee.LastLoginDate // "never") | \(.Assignee.Profile.Name // "-")"'
echo "== GROUP CONTENTS (group | permission set | license it needs)"
q "SELECT PermissionSetGroup.DeveloperName, PermissionSet.Name, PermissionSet.License.MasterLabel FROM PermissionSetGroupComponent WHERE PermissionSetGroup.DeveloperName IN ('RLM_RCB','RLM_RMI')" | jq -r '.[] | "  \(.PermissionSetGroup.DeveloperName) | \(.PermissionSet.Name) | \(.PermissionSet.License.MasterLabel // "-")"'
echo "== BHAVANA: does she hold the licenses these groups need?"
q "SELECT PermissionSetLicense.MasterLabel FROM PermissionSetLicenseAssign WHERE Assignee.Username = 'bhavana.n@streamforcesolutions.com.mindbodysfs'" | jq -r '[.[].PermissionSetLicense.MasterLabel] | sort | join(", ")'
