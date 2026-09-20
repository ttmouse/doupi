#!/bin/bash
# Compile and run the sidebar hit-test regression check.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build
swiftc -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macos14 \
    -module-cache-path .build/sidebar-hit-test-cache \
    Sources/DoupiViewer/EventPassthroughView.swift \
    Scripts/check-sidebar-hit-test.swift \
    -o .build/check-sidebar-hit-test
.build/check-sidebar-hit-test
