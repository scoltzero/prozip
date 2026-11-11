#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <app-bundle> [debug|release] [bin-dir]" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
APP_BUNDLE="$1"
BUILD_CONFIG="${2:-debug}"
case "$BUILD_CONFIG" in debug|release) ;; *) echo "Invalid build configuration" >&2; exit 2;; esac
if [ ! -d "$APP_BUNDLE/Contents" ] || [ ! -f "$APP_BUNDLE/Contents/Info.plist" ]; then
    echo "Expected an existing, packaged app bundle: $APP_BUNDLE" >&2
    exit 2
fi
APP_BUNDLE="$(cd "$APP_BUNDLE" && pwd -P)"
HOST_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
if [ "$HOST_ID" != "org.prozip.ProZip" ]; then
    echo "Expected host bundle identifier org.prozip.ProZip" >&2
    exit 2
fi

if [ "$#" -eq 3 ]; then
    BIN_DIR="$3"
else
    cd "$ROOT_DIR"
    swift build -c "$BUILD_CONFIG" --product ProZipQuickLook
    BIN_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
fi
EXECUTABLE="$BIN_DIR/ProZipQuickLook"
if [ ! -x "$EXECUTABLE" ]; then
    echo "Quick Look executable not found: $EXECUTABLE" >&2
    exit 1
fi
# The SDK bootstrap must be selected by the target's -e _NSExtensionMain link flag.
UNDEFINED_SYMBOLS="$(/usr/bin/nm -u "$EXECUTABLE")"
if ! /usr/bin/grep -Eq '^[[:space:]]*_NSExtensionMain$' <<< "$UNDEFINED_SYMBOLS"; then
    echo "Quick Look binary does not use the SDK NSExtensionMain entry" >&2
    exit 1
fi
LINKED_LIBRARIES="$(/usr/bin/otool -L "$EXECUTABLE")"
if /usr/bin/grep -Eq '/opt/homebrew/|/usr/local/' <<< "$LINKED_LIBRARIES"; then
    echo "Quick Look binary must link system libraries only" >&2
    exit 1
fi

PLUGINS="$APP_BUNDLE/Contents/PlugIns"
APPEX="$PLUGINS/ProZipQuickLook.appex"
if [ -L "$PLUGINS" ] || [ -L "$APPEX" ]; then
    echo "Refusing a symbolic-link extension destination" >&2
    exit 1
fi
mkdir -p "$PLUGINS"
STAGING="$(mktemp -d "$PLUGINS/.ProZipQuickLook-stage.XXXXXX")"
STAGED_APPEX="$STAGING/ProZipQuickLook.appex"
BACKUP="$STAGING/previous.appex"
PUBLISHED=0
cleanup() {
    if [ "$PUBLISHED" -eq 0 ] && [ -d "$BACKUP" ] && [ ! -e "$APPEX" ]; then mv "$BACKUP" "$APPEX" || true; fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$STAGED_APPEX/Contents/MacOS" "$STAGED_APPEX/Contents/Resources"
cp "$EXECUTABLE" "$STAGED_APPEX/Contents/MacOS/ProZipQuickLook"
cp "$ROOT_DIR/Resources/Extensions/QuickLook-Info.plist" "$STAGED_APPEX/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon-Preview.png" "$STAGED_APPEX/Contents/Resources/AppIcon-Preview.png"
mkdir -p "$STAGED_APPEX/Contents/Resources/Licenses/libarchive"
cp "$ROOT_DIR/Sources/CArchive/include/COPYING" "$STAGED_APPEX/Contents/Resources/Licenses/libarchive/COPYING"
cp "$ROOT_DIR/Sources/CArchive/README.md" "$STAGED_APPEX/Contents/Resources/Licenses/libarchive/SOURCE.md"
chmod +x "$STAGED_APPEX/Contents/MacOS/ProZipQuickLook"
for KEY in CFBundleShortVersionString CFBundleVersion; do
    VALUE="$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
    if [ -n "$VALUE" ]; then /usr/libexec/PlistBuddy -c "Set :$KEY $VALUE" "$STAGED_APPEX/Contents/Info.plist"; fi
done
/usr/bin/plutil -lint "$STAGED_APPEX/Contents/Info.plist" "$ROOT_DIR/Resources/Extensions/QuickLook.entitlements"
/usr/bin/codesign --force --sign - --timestamp=none --entitlements "$ROOT_DIR/Resources/Extensions/QuickLook.entitlements" "$STAGED_APPEX"
/usr/bin/codesign --verify --strict "$STAGED_APPEX"
if [ -e "$APPEX" ]; then mv "$APPEX" "$BACKUP"; fi
mv "$STAGED_APPEX" "$APPEX"
PUBLISHED=1
echo "Packaged Quick Look extension: $APPEX"
