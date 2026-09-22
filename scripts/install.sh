#!/bin/bash
# ClipStash one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/Stormblessed-0/ClipStash/main/scripts/install.sh | bash
#
# What it does, in order:
#   1. Downloads the latest release zip from GitHub.
#   2. Puts ClipStash.app in /Applications, or ~/Applications if you are not an admin.
#   3. Clears the download quarantine flag so macOS does not block the first launch
#      (the app is open source but not notarized by Apple).
#   4. Launches ClipStash.
# It never asks for your password and never touches anything else.
set -euo pipefail

REPO="Stormblessed-0/ClipStash"
ZIP_URL="https://github.com/$REPO/releases/latest/download/ClipStash.zip"
APP_NAME="ClipStash.app"

say() { printf '\033[1m▶ %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "ClipStash only runs on macOS."
command -v curl >/dev/null || fail "curl is required."

# Pick a destination the current user can write to.
if [ -w /Applications ]; then
    DEST_DIR="/Applications"
else
    DEST_DIR="$HOME/Applications"
    mkdir -p "$DEST_DIR"
fi
DEST="$DEST_DIR/$APP_NAME"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading the latest ClipStash release…"
curl -fL --progress-bar -o "$TMP/ClipStash.zip" "$ZIP_URL" \
    || fail "Download failed. Check your connection or visit https://github.com/$REPO/releases"

say "Unpacking…"
ditto -x -k "$TMP/ClipStash.zip" "$TMP/unpacked"
[ -d "$TMP/unpacked/$APP_NAME" ] || fail "The download did not contain $APP_NAME."

if pgrep -xq ClipStash; then
    say "Quitting the running copy of ClipStash…"
    pkill -x ClipStash || true
    sleep 1
fi

say "Installing to $DEST…"
rm -rf "$DEST"
ditto "$TMP/unpacked/$APP_NAME" "$DEST"

# Remove the quarantine flag that makes Gatekeeper block unsigned downloads.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

say "Launching ClipStash…"
open "$DEST"

VERSION="$(defaults read "$DEST/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "")"
cat <<EOF

✔ ClipStash ${VERSION} is installed at $DEST and running in your menu bar.

Next steps:
  • When macOS asks, grant Accessibility access so items paste automatically:
    System Settings → Privacy & Security → Accessibility → turn on ClipStash.
  • Press Control + V (⌃V) anywhere to open your clipboard history.
  • ClipStash starts automatically at login. Change that in its Settings.

Everything you copy is stored only on this Mac, in:
  ~/Library/Application Support/ClipStash/
EOF
