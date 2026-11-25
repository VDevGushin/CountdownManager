#!/bin/bash
set -euo pipefail

template=$1
localized_purposes=$2
output=$3

cp "$template" "$output"
if [[ -n "${4:-}" ]]; then
    /usr/bin/plutil -replace CFBundleIdentifier -string "$4" "$output"
fi
for key in NSLocationUsageDescription NSLocationWhenInUseUsageDescription; do
    purpose="$(/usr/bin/plutil -extract "$key" raw "$localized_purposes")"
    /usr/bin/plutil -insert "$key" -string "$purpose" "$output"
done
