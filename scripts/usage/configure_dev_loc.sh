#!/usr/bin/env bash
QSOQL="SELECT QuoteNumber FROM Quote WHERE Hierarchy_Location_Count__c >= 10 ORDER BY CreatedDate DESC LIMIT 3" "$(dirname "$0")/configure_quotes.sh"
