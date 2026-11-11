#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${1:-debug}"
case "$BUILD_CONFIG" in debug|release) ;; *) echo "Invalid build configuration" >&2; exit 2 ;; esac

echo "==> Building ProZip ($BUILD_CONFIG)..."
cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIG"

BIN_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
BIN_PATH="$BIN_DIR/ProZip"
APP_BUNDLE="$ROOT_DIR/build/ProZip.app"

echo "==> Packaging $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/ProZip"
chmod +x "$APP_BUNDLE/Contents/MacOS/ProZip"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
cp -f "$ROOT_DIR/Resources/"*.png "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
cp -f "$ROOT_DIR/Resources/"*.otf "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
cp -rf "$ROOT_DIR/Resources/"*.lproj "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

# Bundle an actual Mach-O engine, not Homebrew's shell wrapper or an external symlink.
SEVEN_ZIP_BIN=""
for CANDIDATE in "$(command -v 7zz || true)" \
    /opt/homebrew/bin/7zz /usr/local/bin/7zz \
    /opt/homebrew/opt/p7zip/lib/p7zip/7z /usr/local/opt/p7zip/lib/p7zip/7z; do
    [ -x "$CANDIDATE" ] || continue
    case "$(/usr/bin/file -bL "$CANDIDATE")" in
        Mach-O*) SEVEN_ZIP_BIN="$CANDIDATE"; break ;;
    esac
done

if [ -n "$SEVEN_ZIP_BIN" ]; then
    while [ -L "$SEVEN_ZIP_BIN" ]; do
        LINK_TARGET="$(readlink "$SEVEN_ZIP_BIN")"
        case "$LINK_TARGET" in
            /*) SEVEN_ZIP_BIN="$LINK_TARGET" ;;
            *) SEVEN_ZIP_BIN="$(dirname "$SEVEN_ZIP_BIN")/$LINK_TARGET" ;;
        esac
    done
    SEVEN_ZIP_DIR="$(cd "$(dirname "$SEVEN_ZIP_BIN")" && pwd -P)"
    LICENSE_DIR=""
    for DOC_DIR in "$SEVEN_ZIP_DIR"/../../share/doc/p7zip/DOC \
        "$SEVEN_ZIP_DIR"/../share/doc/*/DOC "$SEVEN_ZIP_DIR"/../share/doc/* \
        "$SEVEN_ZIP_DIR"/../DOC "$SEVEN_ZIP_DIR"/DOC "$SEVEN_ZIP_DIR"; do
        if [ -f "$DOC_DIR/License.txt" ] && [ -f "$DOC_DIR/copying.txt" ] \
            && [ -f "$DOC_DIR/unRarLicense.txt" ]; then
            LICENSE_DIR="$DOC_DIR"
            break
        fi
    done
    if [ -z "$LICENSE_DIR" ]; then
        echo "Error: 7-Zip license files not found beside $SEVEN_ZIP_BIN" >&2
        exit 1
    fi
    cp -L "$SEVEN_ZIP_BIN" "$APP_BUNDLE/Contents/Resources/7zz"
    chmod +x "$APP_BUNDLE/Contents/Resources/7zz"
    if [ -f "$SEVEN_ZIP_DIR/7z.so" ]; then
        cp -L "$SEVEN_ZIP_DIR/7z.so" "$APP_BUNDLE/Contents/Resources/7z.so"
    elif [[ "$SEVEN_ZIP_BIN" == */lib/p7zip/7z ]]; then
        echo "Error: p7zip engine requires its adjacent 7z.so" >&2
        exit 1
    fi
    mkdir -p "$APP_BUNDLE/Contents/Resources/Licenses/7-Zip"
    for LICENSE_FILE in License.txt copying.txt unRarLicense.txt; do
        cp -L "$LICENSE_DIR/$LICENSE_FILE" "$APP_BUNDLE/Contents/Resources/Licenses/7-Zip/"
    done
fi

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Sign nested code first so the parent signature preserves each extension's sandbox entitlements.
for ENGINE_FILE in 7zz 7z.so; do
    if [ -f "$APP_BUNDLE/Contents/Resources/$ENGINE_FILE" ]; then
        codesign --force --sign - --timestamp=none "$APP_BUNDLE/Contents/Resources/$ENGINE_FILE"
    fi
done
bash "$ROOT_DIR/scripts/build_finder_extension.sh" "$APP_BUNDLE" "$BUILD_CONFIG" "$BIN_DIR"
bash "$ROOT_DIR/scripts/build_quicklook_extension.sh" "$APP_BUNDLE" "$BUILD_CONFIG" "$BIN_DIR"
codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> Successfully packaged: $APP_BUNDLE"
