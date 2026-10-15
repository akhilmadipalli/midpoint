#!/bin/bash
# Points the Homebrew cask at a published release.
#   scripts/update-cask.sh [version] [path/to/homebrew-tap]
# Defaults: version from VERSION, tap checkout at ../homebrew-tap. Review, then commit and push the tap.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(cat VERSION)}"
TAP="${2:-../homebrew-tap}"
CASK="$TAP/Casks/midpoint.rb"
[ -f "$CASK" ] || { echo "No cask at $CASK (clone https://github.com/akhilmadipalli/homebrew-tap there)"; exit 1; }

SUMS=$(curl -fsSL "https://github.com/akhilmadipalli/midpoint/releases/download/v$VERSION/SHA256SUMS")
SHA=$(awk -v f="Midpoint-$VERSION.zip" '$2 == f { print $1 }' <<<"$SUMS")
[ -n "$SHA" ] || { echo "Midpoint-$VERSION.zip not found in the v$VERSION release"; exit 1; }

sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
echo "Updated $CASK to $VERSION ($SHA)"
git -C "$TAP" diff --stat
