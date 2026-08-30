#!/bin/bash
# Builds Omakase.app. No Xcode project, no dependencies: swiftc plus a plist.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-$PWD/build/Omakase.app}"
VERSION="${VERSION:-0.1.0}"

swift build -c release --product OmakaseApp
swift build -c release --product omakase

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/OmakaseApp "$APP/Contents/MacOS/Omakase"
# The CLI ships inside the bundle, but NOT next to the app binary: APFS is
# case-insensitive, so MacOS/omakase would overwrite MacOS/Omakase.
cp .build/release/omakase   "$APP/Contents/Resources/omakase"
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

# Ad-hoc signature: not notarisation, but it keeps macOS from killing the app
# outright on Apple silicon. Users still get the unidentified-developer prompt.
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "→ $APP"
