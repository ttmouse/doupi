#!/bin/bash
# Compile and run the file refresh regression check.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build
swiftc -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macos14 \
    -module-cache-path .build/file-change-check-cache \
    Sources/DoupiViewer/FileChangeMonitor.swift \
    Scripts/check-file-change.swift \
    -o .build/check-file-change
.build/check-file-change
