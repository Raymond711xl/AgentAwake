#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist/AgentAwake.app"
RELEASE_DIR="$PROJECT_DIR/dist/release"
STAGING_DIR="$PROJECT_DIR/dist/dmg-staging"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEYCHAIN_PATH="${NOTARY_KEYCHAIN:-}"
VERSION="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$INFO_PLIST")"
DMG_PATH="$RELEASE_DIR/AgentAwake-$VERSION.dmg"
ZIP_PATH="$RELEASE_DIR/AgentAwake-$VERSION.zip"
CHECKSUM_PATH="$RELEASE_DIR/AgentAwake-$VERSION.sha256"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "DEVELOPER_ID_APPLICATION is required for a public release." >&2
    exit 78
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "NOTARY_KEYCHAIN_PROFILE is required for a public release." >&2
    exit 78
fi

"$PROJECT_DIR/scripts/build-app.sh" release universal

for helper in \
    "$APP_DIR/Contents/Helpers/AgentAwakeHook" \
    "$APP_DIR/Contents/Helpers/AgentAwakeHookSetup"; do
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$helper"
done

/usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

/bin/rm -rf "$RELEASE_DIR" "$STAGING_DIR"
/bin/mkdir -p "$RELEASE_DIR" "$STAGING_DIR"
/usr/bin/ditto "$APP_DIR" "$STAGING_DIR/AgentAwake.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/hdiutil create \
    -volname "AgentAwake" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

/usr/bin/codesign \
    --force \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$DMG_PATH"

NOTARY_ARGUMENTS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "$NOTARY_KEYCHAIN_PATH" ]]; then
    NOTARY_ARGUMENTS+=(--keychain "$NOTARY_KEYCHAIN_PATH")
fi

/usr/bin/xcrun notarytool submit \
    "$DMG_PATH" \
    "${NOTARY_ARGUMENTS[@]}" \
    --wait
/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"
/usr/bin/xcrun stapler staple "$APP_DIR"
/usr/bin/xcrun stapler validate "$APP_DIR"
/usr/bin/ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$APP_DIR" \
    "$ZIP_PATH"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_DIR"
/usr/sbin/spctl \
    --assess \
    --type open \
    --context context:primary-signature \
    --verbose=2 \
    "$DMG_PATH"
/usr/bin/hdiutil verify "$DMG_PATH"

(
    cd "$RELEASE_DIR"
    /usr/bin/shasum -a 256 \
        "${DMG_PATH:t}" \
        "${ZIP_PATH:t}" \
        > "${CHECKSUM_PATH:t}"
)

/bin/rm -rf "$STAGING_DIR"

echo "$DMG_PATH"
echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
