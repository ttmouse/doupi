#!/bin/bash
# Compile and run the sidebar multi-keyword search regression check.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build
swiftc -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macos14 \
    -module-cache-path .build/search-query-check-cache \
    Sources/DoupiViewer/SearchQuery.swift \
    Scripts/check-search-query.swift \
    -o .build/check-search-query
.build/check-search-query
