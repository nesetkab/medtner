#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Medtner.app
VERSION=${VERSION:-0.1.0}
mkdir -p build
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -wmo -target arm64-apple-macos15.0 -swift-version 5 \
  $(find Sources -name '*.swift') -o "$APP/Contents/MacOS/Medtner"
strip -x "$APP/Contents/MacOS/Medtner"
clang -O2 -framework CoreFoundation -mmacosx-version-min=15.0 Hook/hook.c -o "$APP/Contents/MacOS/medtner-hook"
strip -x "$APP/Contents/MacOS/medtner-hook"

if [ ! -f build/AppIcon.icns ] || [ Resources/AppIcon.svg -nt build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift scripts/icon.swift Resources/AppIcon.svg build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

LIBRESPOT=$(command -v librespot || true)
if [ -n "$LIBRESPOT" ]; then
  cp "$(realpath "$LIBRESPOT")" "$APP/Contents/Resources/librespot"
  chmod +x "$APP/Contents/Resources/librespot"
else
  echo "warning: librespot not found, run: brew install librespot"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Medtner</string>
  <key>CFBundleDisplayName</key><string>Medtner</string>
  <key>CFBundleIdentifier</key><string>app.medtner</string>
  <key>CFBundleExecutable</key><string>Medtner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key><string>Medtner listens on 127.0.0.1 to finish Spotify sign in.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
du -sh "$APP" | awk '{print "built " $2 " (" $1 ")"}'

if [ "${1:-}" = "dist" ]; then
  rm -f build/Medtner.zip
  ditto -c -k --keepParent "$APP" build/Medtner.zip
  du -sh build/Medtner.zip | awk '{print "packed " $2 " (" $1 ")"}'
fi

if [ "${1:-}" = "install" ]; then
  pkill -x Medtner || true
  rm -rf /Applications/Medtner.app
  cp -R "$APP" /Applications/
  echo "installed /Applications/Medtner.app"
fi
