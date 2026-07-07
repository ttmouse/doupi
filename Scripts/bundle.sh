#!/bin/bash
# ─── Bundle DoupiViewer as a proper .app ───

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_NAME="DoupiViewer"
BUILD_DIR=".build/arm64-apple-macosx/debug"
APP_NAME="${PROJECT_NAME}.app"
CONTENTS="${APP_NAME}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "🔨 Building..."
swift build

echo "📦 Creating .app bundle..."
rm -rf "$APP_NAME"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BUILD_DIR/$PROJECT_NAME" "$MACOS/"

# Copy icon
cp "Scripts/DoupiViewer.icns" "$RESOURCES/"

# Copy highlight.js resources
cp Sources/DoupiViewer/Resources/* "$RESOURCES/"

# Create Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>doupi</string>
    <key>CFBundleDisplayName</key>
    <string>doupi</string>
    <key>CFBundleIdentifier</key>
    <string>com.doupi.viewer</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$PROJECT_NAME</string>
    <key>CFBundleIconFile</key>
    <string>DoupiViewer</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

echo "✅ Built: $APP_NAME"
echo "Run with: open $APP_NAME"
