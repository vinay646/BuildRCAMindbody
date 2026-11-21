#!/usr/bin/env bash
# READ ONLY: prints the QuantumBit quote document page (base64) + document template/asset info
W=$(mktemp -d); cd "$W"; sf project generate --name c >/dev/null 2>&1; cd c
sf project retrieve start --metadata "FlexiPage:RLM_QuantumBit_Quote" --target-org target >/dev/null 2>&1
f=$(find . -name "RLM_QuantumBit_Quote.flexipage-meta.xml"); echo "@@@@ RLM_QuantumBit_Quote.flexipage-meta.xml"; base64 -w0 "$f"; echo
echo "assets: $(sf data query --query "SELECT DeveloperName, MasterLabel FROM ContentAsset" --target-org target --json | jq -c '[.result.records[] | .DeveloperName]')"
echo "doc templates: $(sf data query --query "SELECT Name, Type, IsActive FROM DocumentTemplate" --target-org target --json 2>/dev/null | jq -c '[.result.records[]? | {Name, Type, IsActive}]')"
