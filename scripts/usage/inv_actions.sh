#!/usr/bin/env bash
# Read-only: list standard invocable actions about invoices/billing
API="/services/data/v$ORG_API"
sf api request rest "$API/actions/standard" --target-org target 2>/dev/null | grep -o '"name" *: *"[^"]*"' | grep -i 'invoic\|billing' 
