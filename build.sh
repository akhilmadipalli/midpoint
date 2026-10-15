#!/bin/sh
# Builds Midpoint.app.  Usage: ./build.sh [--install]
#
# Signing: uses $MIDPOINT_SIGN_IDENTITY, else your first "Apple Development"/"Developer ID" identity,
# else ad-hoc. A real identity keeps macOS's Accessibility permission across rebuilds; with ad-hoc
# signing you must re-enable Midpoint in Accessibility after every rebuild.
set -e
cd "$(dirname "$0")"
APP=build/Midpoint.app
VERSION=0.3.0

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -o "$APP/Contents/MacOS/Midpoint" Sources/*.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.akhilmadipalli.midpoint</string>
  <key>CFBundleName</key><string>Midpoint</string>
  <key>CFBundleExecutable</key><string>Midpoint</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

IDENTITY="${MIDPOINT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -nE 's/.*"((Apple Development|Developer ID Application):[^"]*)".*/\1/p' | head -1)}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Signed ad-hoc (re-enable Midpoint in Accessibility after each rebuild)"
fi
echo "Built $APP"

if [ "$1" = "--install" ]; then
  pkill -x Midpoint || true
  rm -rf /Applications/Midpoint.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Midpoint.app"
fi
