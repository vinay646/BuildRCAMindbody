#!/usr/bin/env bash
# CHANGES the org: gives the target user every permission set license, permission set and permission set group the
# source user has (skips ones already assigned). SOURCE / TARGET = usernames.
set -uo pipefail
SOURCE=${SOURCE:-admin@mindbodysfs.com}; TARGET=${TARGET:-bhavana.n@streamforcesolutions.com.mindbodysfs}
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]?]'; }
S=$(q "SELECT Id FROM User WHERE Username = '$SOURCE'" | jq -r '.[0].Id'); T=$(q "SELECT Id FROM User WHERE Username = '$TARGET'" | jq -r '.[0].Id')
echo "source $SOURCE ($S) -> target $TARGET ($T)"
[ "$S" = null ] || [ "$T" = null ] && { echo "user not found"; exit 1; }
create() { r=$(sf data create record --sobject "$1" --values "$2" --target-org target --json 2>&1); if echo "$r" | jq -e '.status == 0' >/dev/null 2>&1; then echo "  OK   $3"; else echo "  FAIL $3: $(echo "$r" | jq -r '.message // .' 2>/dev/null | head -c 200)"; fi; }
echo "== PERMISSION SET LICENSES"
HAVE=$(q "SELECT PermissionSetLicenseId FROM PermissionSetLicenseAssign WHERE AssigneeId = '$T'" | jq -r '.[].PermissionSetLicenseId')
q "SELECT PermissionSetLicenseId, PermissionSetLicense.MasterLabel FROM PermissionSetLicenseAssign WHERE AssigneeId = '$S'" | jq -r '.[] | "\(.PermissionSetLicenseId)|\(.PermissionSetLicense.MasterLabel)"' | while IFS='|' read -r id label; do
  echo "$HAVE" | grep -q "$id" && { echo "  SKIP $label (already)"; continue; }
  create PermissionSetLicenseAssign "AssigneeId=$T PermissionSetLicenseId=$id" "$label"
done
echo "== PERMISSION SETS"
HAVE=$(q "SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = '$T'" | jq -r '.[].PermissionSetId')
q "SELECT PermissionSetId, PermissionSet.Label FROM PermissionSetAssignment WHERE AssigneeId = '$S' AND PermissionSet.IsOwnedByProfile = false AND PermissionSetGroupId = null" | jq -r '.[] | "\(.PermissionSetId)|\(.PermissionSet.Label)"' | while IFS='|' read -r id label; do
  echo "$HAVE" | grep -q "$id" && { echo "  SKIP $label (already)"; continue; }
  create PermissionSetAssignment "AssigneeId=$T PermissionSetId=$id" "$label"
done
echo "== PERMISSION SET GROUPS"
HAVE=$(q "SELECT PermissionSetGroupId FROM PermissionSetAssignment WHERE AssigneeId = '$T' AND PermissionSetGroupId != null" | jq -r '.[].PermissionSetGroupId')
q "SELECT PermissionSetGroupId, PermissionSetGroup.MasterLabel FROM PermissionSetAssignment WHERE AssigneeId = '$S' AND PermissionSetGroupId != null" | jq -r '.[] | "\(.PermissionSetGroupId)|\(.PermissionSetGroup.MasterLabel)"' | while IFS='|' read -r id label; do
  echo "$HAVE" | grep -q "$id" && { echo "  SKIP $label (already)"; continue; }
  create PermissionSetAssignment "AssigneeId=$T PermissionSetGroupId=$id" "$label"
done
echo "== TARGET NOW: $(q "SELECT COUNT() FROM PermissionSetLicenseAssign WHERE AssigneeId = '$T'" | jq -c .) licenses"
sf data query --query "SELECT COUNT(Id) n FROM PermissionSetLicenseAssign WHERE AssigneeId = '$T'" --target-org target --json | jq -c '.result.records'
sf data query --query "SELECT COUNT(Id) n FROM PermissionSetAssignment WHERE AssigneeId = '$T' AND PermissionSet.IsOwnedByProfile = false" --target-org target --json | jq -c '.result.records'
