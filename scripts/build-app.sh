#!/bin/bash
# Builds ClipStash.app and a zip ready for GitHub Releases.
#
# Usage:  scripts/build-app.sh [version]
# Output: dist/ClipStash.app and dist/ClipStash-<version>.zip
#
# Requires only the Xcode Command Line Tools (xcode-select --install).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(cat VERSION)}"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
APP_NAME="ClipStash"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "▶ Building $APP_NAME $VERSION (release)"

# Some Command Line Tools releases ship a newest SDK whose SwiftUI needs a
# macro plugin that only full Xcode provides. If the default SDK cannot
# compile SwiftUI, fall back to the newest older SDK that can.
choose_sdk() {
    if [ -n "${SDKROOT:-}" ]; then return; fi
    local probe
    probe="$(mktemp -d)"
    cat > "$probe/probe.swift" <<'EOF'
import SwiftUI
struct P: View { @State var n = 0; var body: some View { Text("\(n)") } }
EOF
    if xcrun swiftc -parse-as-library -typecheck "$probe/probe.swift" >/dev/null 2>&1; then
        rm -rf "$probe"; return
    fi
    local sdk
    for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk 2>/dev/null | sort -rV); do
        if SDKROOT="$sdk" xcrun swiftc -parse-as-library -typecheck "$probe/probe.swift" >/dev/null 2>&1; then
            echo "  (default SDK cannot compile SwiftUI here; using $(basename "$sdk"))"
            export SDKROOT="$sdk"
            break
        fi
    done
    rm -rf "$probe"
}
choose_sdk

# Universal binary (Apple Silicon + Intel). Fall back to the host arch if the
# toolchain cannot produce a fat binary.
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    echo "  (universal build unavailable, building for host architecture)"
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature with a stable designated requirement.
#
# By default an ad-hoc signature's requirement is the hash of the exact
# binary, so every rebuild or update looks like a different app to macOS and
# the user's Accessibility grant silently stops matching. Pinning the
# requirement to the bundle identifier keeps the grant valid across updates.
codesign --force --deep --sign - \
    --identifier com.clipstash.app \
    --requirements '=designated => identifier "com.clipstash.app"' \
    "$APP"

ZIP="$DIST/$APP_NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
# Stable name so https://github.com/<repo>/releases/latest/download/ClipStash.zip
# always points at the newest release (used by the README and install.sh).
cp "$ZIP" "$DIST/$APP_NAME.zip"

echo "✔ Built $APP"
echo "✔ Packaged $ZIP (and $DIST/$APP_NAME.zip)"
