#!/bin/sh
# Builds Midpoint.app.
#
#   ./build.sh             build for this Mac into build/Midpoint.app
#   ./build.sh --install   build, then copy to /Applications (quits a running copy first)
#   ./build.sh --release   universal (arm64 + x86_64) build, packaged into dist/ as .zip, .dmg and SHA256SUMS
#
# Signing: uses $MIDPOINT_SIGN_IDENTITY if set. Otherwise local builds use your first "Apple Development"
# or "Developer ID Application" identity, and release builds use a "Developer ID Application" identity.
# With neither, the app is signed ad-hoc, and macOS asks for Accessibility again after each rebuild.
set -e
cd "$(dirname "$0")"

VERSION=$(cat VERSION)
APP=build/Midpoint.app
MODE="$1"
MIN_MACOS=14.0

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [ "$MODE" = "--release" ]; then
  for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos$MIN_MACOS" -o "build/Midpoint-$arch" Sources/*.swift
  done
  lipo -create -output "$APP/Contents/MacOS/Midpoint" build/Midpoint-arm64 build/Midpoint-x86_64
  rm build/Midpoint-arm64 build/Midpoint-x86_64
else
  swiftc -O -target "$(uname -m)-apple-macos$MIN_MACOS" -o "$APP/Contents/MacOS/Midpoint" Sources/*.swift
fi

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
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

if [ "$MODE" = "--release" ]; then
  IDENTITY_PATTERN='Developer ID Application'
else
  IDENTITY_PATTERN='Apple Development|Developer ID Application'
fi
IDENTITY="${MIDPOINT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -nE "s/.*\"(($IDENTITY_PATTERN):[^\"]*)\".*/\1/p" | head -1)}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Signed ad-hoc"
fi
echo "Built $APP ($VERSION)"

case "$MODE" in
  --install)
    pkill -x Midpoint || true
    rm -rf /Applications/Midpoint.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/Midpoint.app"
    ;;
  --release)
    rm -rf dist && mkdir dist
    ditto -c -k --keepParent "$APP" "dist/Midpoint-$VERSION.zip"
    STAGE=build/dmg && rm -rf "$STAGE" && mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "Midpoint $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "dist/Midpoint-$VERSION.dmg"
    rm -rf "$STAGE"
    # Unversioned copies give stable "latest" URLs: .../releases/latest/download/Midpoint.zip
    cp "dist/Midpoint-$VERSION.zip" dist/Midpoint.zip
    cp "dist/Midpoint-$VERSION.dmg" dist/Midpoint.dmg
    (cd dist && shasum -a 256 Midpoint*.zip Midpoint*.dmg > SHA256SUMS)
    echo "Packaged:" && ls -1 dist
    ;;
esac
