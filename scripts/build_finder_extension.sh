#!/usr/bin/env bash
set -euo pipefail

FINDER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FINDER_APP="${1:?Usage: build_finder_extension.sh <app-bundle> [debug|release] [bin-dir]}"
FINDER_CONFIG="${2:-debug}"
FINDER_BIN_DIR="${3:-}"
case "$FINDER_CONFIG" in debug|release) ;; *) echo "Invalid build configuration" >&2; exit 2 ;; esac
case "$FINDER_APP" in *.app) ;; *) echo "Expected an app bundle" >&2; exit 2 ;; esac
if [ ! -f "$FINDER_APP/Contents/Info.plist" ]; then
    echo "Host app Info.plist not found" >&2
    exit 2
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$FINDER_APP/Contents/Info.plist")" != "org.prozip.ProZip" ]; then
    echo "Expected the ProZip host app" >&2
    exit 2
fi
if [ "$#" -lt 3 ]; then
    swift build --package-path "$FINDER_ROOT" -c "$FINDER_CONFIG" --product ProZipFinderSync
    FINDER_BIN_DIR="$(swift build --package-path "$FINDER_ROOT" -c "$FINDER_CONFIG" --show-bin-path)"
elif [ -z "$FINDER_BIN_DIR" ]; then
    echo "Expected a nonempty binary directory" >&2
    exit 2
fi
FINDER_BINARY="$FINDER_BIN_DIR/ProZipFinderSync"
if [ ! -x "$FINDER_BINARY" ]; then echo "Finder extension binary not found" >&2; exit 2; fi
case "$(/usr/bin/file -bL "$FINDER_BINARY")" in Mach-O*) ;; *) echo "Expected a Mach-O Finder extension" >&2; exit 2 ;; esac
if ! /usr/bin/nm -u "$FINDER_BINARY" | /usr/bin/grep '_NSExtensionMain$' >/dev/null; then
    echo "Finder extension must link the SDK NSExtensionMain entry point" >&2
    exit 2
fi

FINDER_PLUGINS="$FINDER_APP/Contents/PlugIns"
mkdir -p "$FINDER_PLUGINS"
FINDER_STAGE_ROOT="$(mktemp -d "$FINDER_PLUGINS/.ProZipFinderSync.XXXXXX")"
FINDER_STAGE="$FINDER_STAGE_ROOT/ProZipFinderSync.appex"
trap 'rm -rf "$FINDER_STAGE_ROOT"' EXIT
mkdir -p "$FINDER_STAGE/Contents/MacOS"
cp -L "$FINDER_BINARY" "$FINDER_STAGE/Contents/MacOS/ProZipFinderSync"
chmod +x "$FINDER_STAGE/Contents/MacOS/ProZipFinderSync"
cp "$FINDER_ROOT/Resources/Extensions/FinderSync-Info.plist" "$FINDER_STAGE/Contents/Info.plist"
for FINDER_VERSION_KEY in CFBundleVersion CFBundleShortVersionString; do
    FINDER_VERSION="$(/usr/libexec/PlistBuddy -c "Print :$FINDER_VERSION_KEY" "$FINDER_APP/Contents/Info.plist")"
    /usr/libexec/PlistBuddy -c "Set :$FINDER_VERSION_KEY $FINDER_VERSION" "$FINDER_STAGE/Contents/Info.plist"
done
printf 'XPC!????' > "$FINDER_STAGE/Contents/PkgInfo"
plutil -lint "$FINDER_STAGE/Contents/Info.plist" "$FINDER_ROOT/Resources/Extensions/FinderSync.entitlements"
codesign --force --sign - --timestamp=none --entitlements "$FINDER_ROOT/Resources/Extensions/FinderSync.entitlements" "$FINDER_STAGE"
codesign --verify --strict "$FINDER_STAGE"
FINDER_DEST="$FINDER_PLUGINS/ProZipFinderSync.appex"
rm -rf "$FINDER_DEST"
mv "$FINDER_STAGE" "$FINDER_DEST"
codesign --verify --strict "$FINDER_DEST"
echo "Packaged Finder extension: $FINDER_DEST"
