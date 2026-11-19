#!/usr/bin/env bash
# READ ONLY: status and versions of the coupon flows (tooling API).
set -uo pipefail
sf data query --use-tooling-api --query "SELECT DeveloperName, ActiveVersion.VersionNumber, LatestVersion.VersionNumber, LastModifiedDate, LastModifiedBy.Name FROM FlowDefinition WHERE DeveloperName IN ('MB_Quote_Coupon_Code','MB_Quote_Line_Coupon_Code')" --target-org target --json | jq -c '.result.records[]? | del(.attributes)' || true
sf data query --use-tooling-api --query "SELECT Definition.DeveloperName, VersionNumber, Status, LastModifiedDate, LastModifiedBy.Name FROM Flow WHERE Definition.DeveloperName IN ('MB_Quote_Coupon_Code','MB_Quote_Line_Coupon_Code') ORDER BY VersionNumber" --target-org target --json | jq -c '.result.records[]? | del(.attributes)' || true
