#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist/AgentAwake.app"
RELEASE_DIR="$PROJECT_DIR/dist/release"
STAGING_ROOT="$PROJECT_DIR/dist/dmg-staging"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$INFO_PLIST")"
APPLE_SILICON_DMG="$RELEASE_DIR/AgentAwake-$VERSION-Apple-Silicon.dmg"
INTEL_DMG="$RELEASE_DIR/AgentAwake-$VERSION-Intel.dmg"
CHECKSUM_PATH="$RELEASE_DIR/AgentAwake-$VERSION.sha256"

package_architecture() {
    local architecture="$1"
    local dmg_path="$2"
    local staging_directory="$STAGING_ROOT/$architecture"

    "$PROJECT_DIR/scripts/build-app.sh" release "$architecture"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

    for executable in \
        "$APP_DIR/Contents/MacOS/AgentAwake" \
        "$APP_DIR/Contents/Helpers/AgentAwakeHook" \
        "$APP_DIR/Contents/Helpers/AgentAwakeHookSetup"; do
        actual_architecture="$(/usr/bin/lipo -archs "$executable")"
        if [[ "$actual_architecture" != "$architecture" ]]; then
            echo "Expected $architecture but found $actual_architecture: $executable" >&2
            exit 65
        fi
    done

    /bin/rm -rf "$staging_directory"
    /bin/mkdir -p "$staging_directory"
    /usr/bin/ditto "$APP_DIR" "$staging_directory/AgentAwake.app"
    /bin/ln -s /Applications "$staging_directory/Applications"

    /usr/bin/hdiutil create \
        -volname "AgentAwake" \
        -srcfolder "$staging_directory" \
        -ov \
        -format UDZO \
        "$dmg_path"
    /usr/bin/hdiutil verify "$dmg_path"
}

/bin/rm -rf "$RELEASE_DIR" "$STAGING_ROOT"
/bin/mkdir -p "$RELEASE_DIR" "$STAGING_ROOT"

package_architecture arm64 "$APPLE_SILICON_DMG"
package_architecture x86_64 "$INTEL_DMG"

(
    cd "$RELEASE_DIR"
    /usr/bin/shasum -a 256 \
        "${APPLE_SILICON_DMG:t}" \
        "${INTEL_DMG:t}" \
        > "${CHECKSUM_PATH:t}"
)

/bin/rm -rf "$STAGING_ROOT"

echo "$APPLE_SILICON_DMG"
echo "$INTEL_DMG"
echo "$CHECKSUM_PATH"
