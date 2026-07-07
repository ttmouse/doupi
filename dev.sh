#!/bin/bash
# ─── Build + package DoupiViewer ───
# Usage:
#   ./dev.sh            # debug build + package + open
#   ./dev.sh build      # debug build + package only
#   ./dev.sh release    # release build + package
#   ./dev.sh watch      # watch sources & auto-rebuild

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DoupiViewer"
PROJECT_DIR="$PWD"

package() {
    local config="$1"  # "debug" or "release"

    if [ "$config" = "release" ]; then
        binary="$PROJECT_DIR/.build/release/$APP_NAME"
    else
        binary="$PROJECT_DIR/.build/arm64-apple-macosx/debug/$APP_NAME"
    fi

    app_bundle="$PROJECT_DIR/.build/$config/$APP_NAME.app"
    macos_dir="$app_bundle/Contents/MacOS"
    resources_dir="$app_bundle/Contents/Resources"

    echo "📦 Packaging $config bundle..."
    rm -rf "$app_bundle"
    mkdir -p "$macos_dir" "$resources_dir"

    cp "$binary" "$macos_dir/$APP_NAME"
    cp -r "$PROJECT_DIR/Sources/$APP_NAME/Resources/"* "$resources_dir/"
    cp "$PROJECT_DIR/Sources/$APP_NAME/Resources/Info.plist" "$app_bundle/Contents/Info.plist"

    # Ad-hoc sign (required for runtime on Apple Silicon)
    codesign --force --sign - "$app_bundle" 2>/dev/null || true

    echo "✅ $app_bundle"
}

case "${1:-run}" in
    release)
        echo "🔨 Release build..."
        swift build -c release --disable-sandbox
        package release
        ;;
    build)
        echo "🔨 Debug build..."
        swift build --disable-sandbox
        package debug
        ;;
    run)
        echo "🔨 Debug build..."
        swift build --disable-sandbox
        package debug
        echo "🚀 Opening..."
        open ".build/debug/$APP_NAME.app"
        ;;
    watch)
        WATCH_DIR="Sources/$APP_NAME"
        echo "👀 Watching $WATCH_DIR for changes..."
        while true; do
            /usr/bin/find "$WATCH_DIR" -name "*.swift" -newer "$WATCH_DIR/.watch_stamp" 2>/dev/null \
                | grep -q . && {
                touch "$WATCH_DIR/.watch_stamp"
                echo "🔄 Change detected, rebuilding..."
                swift build --disable-sandbox 2>&1 && {
                    package debug
                    echo "✅ Rebuilt at $(date '+%H:%M:%S')"
                } || echo "❌ Build failed"
            }
            [ -f "$WATCH_DIR/.watch_stamp" ] || touch "$WATCH_DIR/.watch_stamp"
            sleep 1
        done
        ;;
    *)
        echo "Usage: $0 [run|build|release|watch]"
        exit 1
        ;;
esac
