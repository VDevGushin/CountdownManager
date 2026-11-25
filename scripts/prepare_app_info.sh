#!/bin/bash
set -euo pipefail

template=$1
localized_purposes=$2
output=$3

cp "$template" "$output"
for key in NSLocationUsageDescription NSLocationWhenInUseUsageDescription; do
    purpose="$(/usr/bin/plutil -extract "$key" raw "$localized_purposes")"
    /usr/bin/plutil -insert "$key" -string "$purpose" "$output"
done
