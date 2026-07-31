#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE_ICON="$PROJECT_DIR/Resources/AppIcon.png"
OUTPUT_ICON="$PROJECT_DIR/Resources/AppIcon.icns"
ICON_TMP_ROOT="$(/usr/bin/mktemp -d /private/tmp/agentawake-icon.XXXXXX)"
ICONSET_DIR="$ICON_TMP_ROOT/AppIcon.iconset"

cleanup() {
    /bin/rm -rf "$ICON_TMP_ROOT"
}
trap cleanup EXIT

if [[ ! -f "$SOURCE_ICON" ]]; then
    echo "Missing source icon: $SOURCE_ICON" >&2
    exit 66
fi

/bin/mkdir -p "$ICONSET_DIR"

render_icon() {
    local pixels="$1"
    local filename="$2"

    /usr/bin/sips \
        -z "$pixels" "$pixels" \
        "$SOURCE_ICON" \
        --out "$ICONSET_DIR/$filename" \
        >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

CLANG_MODULE_CACHE_PATH="/private/tmp/agentawake-icon-clang-cache" \
SWIFT_MODULECACHE_PATH="/private/tmp/agentawake-icon-swift-cache" \
/usr/bin/swift \
    "$PROJECT_DIR/scripts/pack-icon.swift" \
    "$ICONSET_DIR" \
    "$OUTPUT_ICON"

echo "$OUTPUT_ICON"
