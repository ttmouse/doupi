#!/bin/bash
# Compile and run the folder "reveal in Finder" location regression check.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build
swiftc -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macos14 \
    -module-cache-path .build/finder-location-check-cache \
    Sources/DoupiViewer/LibraryFolders.swift \
    Scripts/check-finder-location.swift \
    -o .build/check-finder-location
.build/check-finder-location
