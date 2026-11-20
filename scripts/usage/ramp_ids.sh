#!/usr/bin/env bash
# READ ONLY: lines of ramp probe quote 00000222 including deleted ones
sf data query --all-rows --query "SELECT Id, IsDeleted, Product2.ProductCode, QuoteLineGroupId, StartDate, EndDate, RampIdentifier, SegmentIdentifier, CreatedDate, LastModifiedDate FROM QuoteLineItem WHERE QuoteId='0Q0hm00000078NRCAY'" --target-org target 2>&1 | tail -8
