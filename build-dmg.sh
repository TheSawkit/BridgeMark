#!/usr/bin/env bash
# build-dmg.sh — Builds a signed, distributable BridgeMark.dmg
#
# Usage:
#   ./build-dmg.sh                          # ad-hoc signing (dev/test)
#   UNIVERSAL=1 ./build-dmg.sh              # Universal Binary (arm64 + x86_64)
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./build-dmg.sh
#   CODESIGN_IDENTITY="..." NOTARIZE=1 \
#     APPLE_ID="..." APPLE_TEAM_ID="..." \
#     APPLE_APP_PASSWORD="..." ./build-dmg.sh   # full release flow
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
APP_NAME="BridgeMark"
VERSION="1.0"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"    # "-" = ad-hoc
NOTARIZE="${NOTARIZE:-0}"
UNIVERSAL="${UNIVERSAL:-0}"

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCES="$ROOT/Sources/$APP_NAME"
DIST="$ROOT/dist"
STAGING="$(mktemp -d)"
APP_BUNDLE="$STAGING/$APP_NAME.app"
ICNS="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

# ── Cleanup on exit (success or failure) ─────────────────────────────────────
trap 'rm -rf "$STAGING"' EXIT

# ── Dependency check ──────────────────────────────────────────────────────────
command -v create-dmg &>/dev/null \
  || { echo "❌  create-dmg introuvable — brew install create-dmg"; exit 1; }

# ── Build ─────────────────────────────────────────────────────────────────────
echo "🔨  Compilation Release..."
mkdir -p "$DIST"
cd "$ROOT"

if [[ "$UNIVERSAL" == "1" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BINARY="$ROOT/.build/apple/Products/Release/$APP_NAME"
else
  swift build -c release
  BINARY="$ROOT/.build/release/$APP_NAME"
fi

[[ -f "$BINARY" ]] || { echo "❌  Binaire introuvable : $BINARY"; exit 1; }

# ── App bundle structure ──────────────────────────────────────────────────────
echo "📦  Assemblage du bundle .app..."
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY"             "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SOURCES/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' >      "$APP_BUNDLE/Contents/PkgInfo"

# ── Compile .xcstrings → lproj/strings (compatibility macOS 13+) ──────────────
echo "🌍  Localisation..."
python3 - "$SOURCES/Localizable.xcstrings" "$APP_BUNDLE/Contents/Resources" << 'PYEOF'
import json, os, sys

src, out = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)

source_lang = data.get("sourceLanguage", "fr")
strings     = data.get("strings", {})
langs       = {lang for e in strings.values() for lang in e.get("localizations", {}).keys()}

for lang in langs:
    lproj = os.path.join(out, f"{lang}.lproj")
    os.makedirs(lproj, exist_ok=True)
    with open(os.path.join(lproj, "Localizable.strings"), "w", encoding="utf-8") as f:
        for key, entry in strings.items():
            locs = entry.get("localizations", {})
            val  = (locs.get(lang) or locs.get(source_lang, {})).get("stringUnit", {}).get("value", key)
            ek   = key.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            ev   = val.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            f.write(f'"{ek}" = "{ev}";\n')
    print(f"  ✓ {lang}.lproj/Localizable.strings")
PYEOF

# ── App icon ──────────────────────────────────────────────────────────────────
echo "🎨  Icône..."
ICONSRC="$SOURCES/Assets.xcassets/AppIcon.appiconset"
ICONSET_DIR="$(mktemp -d)"
ICONSET="$ICONSET_DIR/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
  cp "$ICONSRC/icon_${size}x${size}.png"    "$ICONSET/icon_${size}x${size}.png"
  cp "$ICONSRC/icon_${size}x${size}@2x.png" "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$ICONSET_DIR"

# ── Code signing ──────────────────────────────────────────────────────────────
echo "✍️   Signature (identity: ${CODESIGN_IDENTITY})..."
find "$APP_BUNDLE" -exec xattr -c {} \; 2>/dev/null || true

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  codesign \
    --force \
    --options runtime \
    --entitlements "$ROOT/BridgeMark.entitlements" \
    --sign "$CODESIGN_IDENTITY" \
    --timestamp \
    "$APP_BUNDLE"
fi

# ── Notarization ──────────────────────────────────────────────────────────────
if [[ "$NOTARIZE" == "1" ]]; then
  [[ "$CODESIGN_IDENTITY" != "-" ]] \
    || { echo "❌  CODESIGN_IDENTITY requis pour notariser"; exit 1; }
  [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]] \
    || { echo "❌  APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD requis"; exit 1; }

  echo "📬  Notarisation de l'app..."
  APP_ZIP="$DIST/$APP_NAME-$VERSION-notarize.zip"
  ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
  xcrun notarytool submit "$APP_ZIP" \
    --apple-id  "$APPLE_ID" \
    --team-id   "$APPLE_TEAM_ID" \
    --password  "$APPLE_APP_PASSWORD" \
    --wait
  rm -f "$APP_ZIP"
  xcrun stapler staple "$APP_BUNDLE"
fi

# ── DMG ───────────────────────────────────────────────────────────────────────
echo "💿  Création du DMG..."
[[ -f "$DMG" ]] && rm -f "$DMG"

create-dmg \
  --volname        "$APP_NAME $VERSION" \
  --volicon        "$ICNS" \
  --window-pos     200 120 \
  --window-size    540 380 \
  --icon-size      128 \
  --icon           "$APP_NAME.app" 160 185 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link  380 185 \
  --no-internet-enable \
  --hdiutil-quiet \
  "$DMG" \
  "$STAGING"

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
  codesign --sign "$CODESIGN_IDENTITY" --timestamp "$DMG"
fi

echo ""
echo "✅  $DMG"
