#!/bin/bash
# Compile and run the version family regression check.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build
swiftc -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macos14 \
    -module-cache-path .build/version-families-check-cache \
    Sources/DoupiViewer/LibraryFolders.swift \
    Sources/DoupiViewer/VersionFamilies.swift \
    Sources/DoupiViewer/DocumentTitles.swift \
    Scripts/check-version-families.swift \
    -o .build/check-version-families
.build/check-version-families
