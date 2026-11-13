#!/usr/bin/env bash
# Reproduce "Failed to fetch promotions ... ProductCategory" : record access + call eligible-promotions directly.
set -uo pipefail
API="/services/data/v$ORG_API"
q() { sf data query --query "$1" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)] // .message'; }
rest() { sf api request rest "$API$2" --method "$1" ${3:+--body "$3"} --target-org target 2>&1; }
CAT=0ZGhm0000003Fk5GAE; CATALOG=0ZShm0000003JCbGAM
echo "ME $(sf org display --target-org target --json | jq -r '.result.username')"
echo "SHARING MODEL $(sf data query --use-tooling-api --query "SELECT QualifiedApiName, InternalSharingModel, ExternalSharingModel FROM EntityDefinition WHERE QualifiedApiName IN ('ProductCatalog','ProductCategory','Promotion')" --target-org target --json | jq -c '[.result.records[]? | del(.attributes)]')"
echo "CATALOG $(q "SELECT Name, OwnerId, Owner.Username, CatalogType FROM ProductCatalog WHERE Id = '$CATALOG'")"
USERS=$(q "SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSet.Name = 'PromotionViewer'" | jq -r '.[].AssigneeId')
for U in $USERS; do
  echo "USER $(q "SELECT Username, Profile.Name FROM User WHERE Id = '$U'")"
  echo "  access category $(q "SELECT RecordId, HasReadAccess FROM UserRecordAccess WHERE UserId = '$U' AND RecordId = '$CAT'")"
  echo "  access catalog $(q "SELECT RecordId, HasReadAccess FROM UserRecordAccess WHERE UserId = '$U' AND RecordId = '$CATALOG'")"
  echo "  catalog shares $(q "SELECT UserOrGroupId, AccessLevel, RowCause FROM ProductCatalogShare WHERE ParentId = '$CATALOG'")"
done
ULT=$(q "SELECT Id FROM Product2 WHERE ProductCode = 'MB-ULT'" | jq -r '.[0].Id')
TODAY=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
for B in \
 "{\"cart\":{\"cartDetails\":[{\"activityStartDate\":\"$TODAY\",\"currencyISOCode\":\"USD\",\"cartLineDetails\":[{\"cartLineProduct\":\"$ULT\",\"cartLineProductCategory\":\"$CAT\",\"cartLineProductCatalog\":\"$CATALOG\",\"cartLineItemQuantity\":1,\"cartLineUnitPrice\":449,\"cartLineItemAmount\":449}]}]}}" \
 "{\"cart\":{\"cartDetails\":[{\"activityStartDate\":\"$TODAY\",\"currencyISOCode\":\"USD\",\"cartLineDetails\":[{\"cartLineProduct\":\"$ULT\",\"cartLineItemQuantity\":1,\"cartLineUnitPrice\":449,\"cartLineItemAmount\":449}]}]}}" \
 "{\"products\":[{\"productId\":\"$ULT\",\"productCategoryId\":\"$CAT\"}],\"currencyIsoCode\":\"USD\"}" \
 "{\"ruleLibraryApiName\":\"RLM_RuleLibrary\",\"productIds\":[\"$ULT\"],\"productCategoryIds\":[\"$CAT\"]}" ; do
  echo "BODY $B"
  echo "  => $(rest POST /global-promotions-management/eligible-promotions "$B" | tr -d '\n' | head -c 1500)"
done
echo "OTHER GPM $(for p in promotions eligible-promotions/products products promotions/eligible; do echo "$p: $(rest POST /global-promotions-management/$p '{}' | tr -d '\n' | head -c 200)"; done)"
