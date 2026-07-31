#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
ARCHITECTURE_MODE="${2:-universal}"
APP_DIR="$PROJECT_DIR/dist/AgentAwake.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_ICON="$PROJECT_DIR/Resources/AppIcon.icns"
BUILD_ROOT="$PROJECT_DIR/.build/app-bundle"
EXECUTABLES=(AgentAwake AgentAwakeHook AgentAwakeHookSetup)

export CLANG_MODULE_CACHE_PATH="/private/tmp/agentawake-clang-cache"
export SWIFT_MODULECACHE_PATH="/private/tmp/agentawake-swift-cache"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
    echo "Configuration must be debug or release." >&2
    exit 64
fi

if [[ "$ARCHITECTURE_MODE" != "native" \
    && "$ARCHITECTURE_MODE" != "universal" ]]; then
    echo "Architecture mode must be native or universal." >&2
    exit 64
fi

if [[ ! -f "$APP_ICON" ]]; then
    "$PROJECT_DIR/scripts/build-icon.sh"
fi

build_for_architecture() {
    local architecture="$1"
    local triple="${architecture}-apple-macosx13.0"
    local scratch_path="$BUILD_ROOT/$architecture"

    /usr/bin/swift build \
        --package-path "$PROJECT_DIR" \
        --configuration "$CONFIGURATION" \
        --triple "$triple" \
        --scratch-path "$scratch_path" \
        --disable-sandbox >&2

    /usr/bin/swift build \
        --package-path "$PROJECT_DIR" \
        --configuration "$CONFIGURATION" \
        --triple "$triple" \
        --scratch-path "$scratch_path" \
        --disable-sandbox \
        --show-bin-path
}

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$RESOURCES_DIR"

if [[ "$ARCHITECTURE_MODE" == "universal" ]]; then
    ARM64_BIN_DIR="$(build_for_architecture arm64)"
    X86_64_BIN_DIR="$(build_for_architecture x86_64)"

    for executable in $EXECUTABLES; do
        destination="$MACOS_DIR/$executable"
        if [[ "$executable" != "AgentAwake" ]]; then
            destination="$HELPERS_DIR/$executable"
        fi

        /usr/bin/lipo -create \
            "$ARM64_BIN_DIR/$executable" \
            "$X86_64_BIN_DIR/$executable" \
            -output "$destination"
    done
else
    /usr/bin/swift build \
        --package-path "$PROJECT_DIR" \
        --configuration "$CONFIGURATION" \
        --disable-sandbox
    NATIVE_BIN_DIR="$PROJECT_DIR/.build/$CONFIGURATION"

    /bin/cp "$NATIVE_BIN_DIR/AgentAwake" "$MACOS_DIR/AgentAwake"
    /bin/cp "$NATIVE_BIN_DIR/AgentAwakeHook" "$HELPERS_DIR/AgentAwakeHook"
    /bin/cp \
        "$NATIVE_BIN_DIR/AgentAwakeHookSetup" \
        "$HELPERS_DIR/AgentAwakeHookSetup"
fi

/bin/cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/bin/cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
/bin/chmod 755 \
    "$MACOS_DIR/AgentAwake" \
    "$HELPERS_DIR/AgentAwakeHook" \
    "$HELPERS_DIR/AgentAwakeHookSetup"

for helper in "$HELPERS_DIR/AgentAwakeHook" \
    "$HELPERS_DIR/AgentAwakeHookSetup"; do
    /usr/bin/codesign --force --sign - "$helper"
done

/usr/bin/codesign \
    --force \
    --sign - \
    "$APP_DIR"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
