#!/bin/bash
# Midpoint installer.
#
#   curl -fsSL https://raw.githubusercontent.com/akhilmadipalli/midpoint/main/scripts/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/akhilmadipalli/midpoint/main/scripts/install.sh | bash -s -- --uninstall
#
# Environment: MIDPOINT_VERSION=0.3.0 to pin a version (default: latest),
#              MIDPOINT_APPDIR=~/Applications to install somewhere other than /Applications,
#              MIDPOINT_NO_OPEN=1 to skip launching after install.
set -euo pipefail

REPO="akhilmadipalli/midpoint"
BUNDLE_ID="io.github.akhilmadipalli.midpoint"
APPDIR="${MIDPOINT_APPDIR:-/Applications}"
APP="$APPDIR/Midpoint.app"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Midpoint only runs on macOS."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || die "Midpoint needs macOS 14 Sonoma or later (you have $(sw_vers -productVersion))."

quit_running() {
  if pgrep -x Midpoint >/dev/null; then
    say "Quitting running Midpoint"
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || pkill -x Midpoint || true
    sleep 1
  fi
}

if [ "${1:-}" = "--uninstall" ]; then
  quit_running
  say "Removing $APP"
  rm -rf "$APP"
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Logs/Midpoint.log"
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  say "Midpoint uninstalled."
  exit 0
fi

if [ -n "${MIDPOINT_VERSION:-}" ]; then
  BASE="https://github.com/$REPO/releases/download/v$MIDPOINT_VERSION"
else
  BASE="https://github.com/$REPO/releases/latest/download"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say "Downloading Midpoint ${MIDPOINT_VERSION:-(latest)}"
curl -fL --progress-bar -o "$TMP/Midpoint.zip" "$BASE/Midpoint.zip" || die "Download failed."
curl -fsSL -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || die "Could not download checksums."

say "Verifying checksum"
expected=$(awk '$2 == "Midpoint.zip" { print $1 }' "$TMP/SHA256SUMS")
actual=$(shasum -a 256 "$TMP/Midpoint.zip" | awk '{ print $1 }')
[ -n "$expected" ] && [ "$expected" = "$actual" ] || die "Checksum mismatch; refusing to install."

ditto -x -k "$TMP/Midpoint.zip" "$TMP/extracted"
[ -d "$TMP/extracted/Midpoint.app" ] || die "Archive did not contain Midpoint.app."

quit_running
mkdir -p "$APPDIR"
if [ -w "$APPDIR" ]; then
  rm -rf "$APP" && mv "$TMP/extracted/Midpoint.app" "$APP"
else
  say "Installing to $APPDIR needs your password"
  sudo rm -rf "$APP" && sudo mv "$TMP/extracted/Midpoint.app" "$APP"
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

say "Installed $APP ($(defaults read "$APP/Contents/Info" CFBundleShortVersionString))"
echo "    Midpoint needs Accessibility access: System Settings → Privacy & Security → Accessibility."
echo "    After an update, turn Midpoint off and on again in that list if middle clicks stop working."
[ -n "${MIDPOINT_NO_OPEN:-}" ] || open "$APP"
