#!/bin/bash
# Compile and run the library mount regression check.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build
swiftc -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macos14 \
    -module-cache-path .build/mounts-check-cache \
    Sources/DoupiViewer/LibraryFolders.swift \
    Sources/DoupiViewer/LibraryMounts.swift \
    Scripts/check-library-mounts.swift \
    -o .build/check-library-mounts
.build/check-library-mounts
