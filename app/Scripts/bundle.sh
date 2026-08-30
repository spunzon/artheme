#!/bin/bash
# Builds Omakase.app and a zip ready to send to someone.
# No Xcode project and no dependencies: swiftc, a plist and ditto.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
OUT="$PWD/build"
APP="$OUT/Omakase.app"

# Universal, so it runs on Apple silicon and on Intel.
#
# SwiftPM's own --arch needs xcbuild, which only comes with the full Xcode, so
# each slice is built separately and stitched together with lipo. That keeps the
# whole build working with just the Command Line Tools.
build_slice() {           # $1 = arch triple, $2 = scratch path
  swift build -c release --product OmakaseApp --scratch-path "$2" \
      -Xswiftc -target -Xswiftc "$1"
  swift build -c release --product omakase --scratch-path "$2" \
      -Xswiftc -target -Xswiftc "$1"
}
build_slice arm64-apple-macos13.0  .build-arm64
build_slice x86_64-apple-macos13.0 .build-x86

BIN="$PWD/.build-universal"
mkdir -p "$BIN"
for product in OmakaseApp omakase; do
  lipo -create ".build-arm64/release/$product" ".build-x86/release/$product" \
       -output "$BIN/$product"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/OmakaseApp" "$APP/Contents/MacOS/Omakase"
# The CLI ships inside, but NOT next to the app binary: APFS is
# case-insensitive, so MacOS/omakase would overwrite MacOS/Omakase.
cp "$BIN/omakase" "$APP/Contents/Resources/omakase"
# Themes travel with the app: a fresh install must not open on an empty grid.
mkdir -p "$APP/Contents/Resources/Themes"
for d in ../themes/*/; do
  [ -f "$d/colors.toml" ] || continue
  mkdir -p "$APP/Contents/Resources/Themes/$(basename "$d")"
  cp "$d"/*.toml "$d"/*.json "$d"/preview.jpg \
     "$APP/Contents/Resources/Themes/$(basename "$d")/" 2>/dev/null || true
done
[ -f Resources/Omakase.icns ] && cp Resources/Omakase.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Omakase</string>
  <key>CFBundleDisplayName</key><string>Omakase</string>
  <key>CFBundleIdentifier</key><string>com.spunzon.omakase</string>
  <key>CFBundleExecutable</key><string>Omakase</string>
  <key>CFBundleIconFile</key><string>Omakase</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Omakase asks System Events to switch macOS between light and dark mode when you change theme.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: not notarisation, but without it macOS refuses to run an
# unsigned binary on Apple silicon at all.
codesign --force --deep --sign - "$APP"

# ditto, not `zip`: it preserves the bundle's symlinks, permissions and signature.
ZIP="$OUT/Omakase-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# A disk image with a shortcut to /Applications: the drag-and-drop most people
# expect from a Mac app, and one less "where do I put this?" for the receiver.
STAGE="$OUT/dmg"
DMG="$OUT/Omakase-${VERSION}.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Omakase" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

echo "→ $APP"
echo "→ $ZIP  ($(du -h "$ZIP" | cut -f1))"
echo "→ $DMG  ($(du -h "$DMG" | cut -f1))"
