#!/bin/bash
# Build DoupiViewer and package into a proper .app bundle

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="DoupiViewer"
BUNDLE_ID="com.doupi.viewer"

echo "🔨 Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build -c release

BINARY="$PROJECT_DIR/.build/release/$APP_NAME"
APP_BUNDLE="$PROJECT_DIR/.build/release/$APP_NAME.app"
APP_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$APP_DIR/MacOS"
RESOURCES_DIR="$APP_DIR/Resources"

echo "📦 Packaging .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp "$BINARY" "$MACOS_DIR/$APP_NAME"

# Copy resources (highlight.js, AppIcon.icns, Info.plist)
cp -r "$PROJECT_DIR/Sources/$APP_NAME/Resources/"* "$RESOURCES_DIR/"
cp "$PROJECT_DIR/Sources/$APP_NAME/Resources/Info.plist" "$APP_DIR/Info.plist"

# Sign the app (required for runtime)
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ Done! App bundle created at:"
echo "   $APP_BUNDLE"
echo ""
echo "To open: open \"$APP_BUNDLE\""
echo "Or copy to /Applications: cp -R \"$APP_BUNDLE\" /Applications/"
