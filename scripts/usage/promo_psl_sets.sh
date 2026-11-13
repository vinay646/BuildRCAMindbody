#!/usr/bin/env bash
set -uo pipefail
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
for l in 'Revenue Management Promotions Run Time' 'Global Promotions Management Basic Psl' 'Revenue Cloud User' 'Salesforce Pricing Run Time'; do
  echo "SETS for $l: $(q "SELECT Name, Label FROM PermissionSet WHERE License.MasterLabel = '$l'" | jq -c '[.[] | .Name]')"
done
echo "USER SETS $(q "SELECT PermissionSet.Name FROM PermissionSetAssignment WHERE Assignee.Username = 'exploremore@rca.com' AND PermissionSet.IsOwnedByProfile = false" | jq -c '[.[] | .PermissionSet.Name]')"
echo "GROUPS $(q "SELECT DeveloperName, MasterLabel FROM PermissionSetGroup WHERE DeveloperName LIKE '%romo%' OR DeveloperName LIKE '%Revenue%' OR DeveloperName LIKE '%Sales%'")"
