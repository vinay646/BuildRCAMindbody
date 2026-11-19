#!/usr/bin/env bash
# READ ONLY: status and versions of the coupon flows.
set -uo pipefail
sf data query --query "SELECT ApiName, Label, IsActive, ActiveVersionId, LatestVersionId, LastModifiedDate, LastModifiedBy.Name FROM FlowDefinitionView WHERE ApiName IN ('MB_Quote_Coupon_Code','MB_Quote_Line_Coupon_Code')" --target-org target --json | jq -c '.result.records[]? | del(.attributes)'
sf data query --query "SELECT FlowDefinitionView.ApiName, VersionNumber, Status, LastModifiedDate, LastModifiedBy.Name FROM FlowVersionView WHERE FlowDefinitionView.ApiName IN ('MB_Quote_Coupon_Code','MB_Quote_Line_Coupon_Code') ORDER BY FlowDefinitionView.ApiName, VersionNumber" --target-org target --json | jq -c '.result.records[]? | del(.attributes)'
