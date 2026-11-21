#!/usr/bin/env bash
../run-apex.sh 2>/dev/null; cd "$(dirname "$0")/../.."; ./scripts/run-apex.sh scripts/usage/apex/approval_groups.apex groups; ./scripts/run-apex.sh scripts/usage/apex/approval_test.apex approval
