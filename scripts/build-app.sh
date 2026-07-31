#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP_DIR="$PROJECT_DIR/dist/AgentAwake.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_ICON="$PROJECT_DIR/Resources/AppIcon.icns"

export CLANG_MODULE_CACHE_PATH="/private/tmp/agentawake-clang-cache"
export SWIFT_MODULECACHE_PATH="/private/tmp/agentawake-swift-cache"

if [[ ! -f "$APP_ICON" ]]; then
    "$PROJECT_DIR/scripts/build-icon.sh"
fi

/usr/bin/swift build \
    --package-path "$PROJECT_DIR" \
    --configuration "$CONFIGURATION" \
    --disable-sandbox

/bin/mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$RESOURCES_DIR"
/bin/cp \
    "$PROJECT_DIR/.build/$CONFIGURATION/AgentAwake" \
    "$MACOS_DIR/AgentAwake"
/bin/cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/bin/cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
/bin/chmod 755 "$MACOS_DIR/AgentAwake"
/bin/cp \
    "$PROJECT_DIR/.build/$CONFIGURATION/AgentAwakeHook" \
    "$HELPERS_DIR/AgentAwakeHook"
/bin/cp \
    "$PROJECT_DIR/.build/$CONFIGURATION/AgentAwakeHookSetup" \
    "$HELPERS_DIR/AgentAwakeHookSetup"
/bin/chmod 755 \
    "$HELPERS_DIR/AgentAwakeHook" \
    "$HELPERS_DIR/AgentAwakeHookSetup"

/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    "$APP_DIR"

echo "$APP_DIR"
