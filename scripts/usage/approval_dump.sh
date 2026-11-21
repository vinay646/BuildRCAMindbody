#!/usr/bin/env bash
# READ ONLY: prints the approval workflow + data subflow XML (compact) so they can be versioned in the repo
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
for fl in RLM_Quote_Smart_Approval RLM_Quote_Approval_Data; do sf project retrieve start --metadata "Flow:$fl" --target-org target >/dev/null 2>&1; done
for f in $(find . -name "*.flow-meta.xml"); do echo "@@@@ $(basename $f)"; base64 -w0 "$f"; echo; done
