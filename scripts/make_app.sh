#!/usr/bin/env bash
#
# Assemble G13Manager.app from the SwiftPM build, write Info.plist, ad-hoc sign,
# and install to a stable path (so TCC permissions persist across rebuilds).
#
# Usage:
#   scripts/make_app.sh [debug|release]
#   INSTALL_DIR=/some/dir scripts/make_app.sh release
#
set -euo pipefail

APP_NAME="G13Manager"
BUNDLE_ID="dev.tuttisound.G13Manager"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

echo "==> Building ($CONFIG)..."
swift build -c "$CONFIG" --package-path "$ROOT" --product "$APP_NAME"

BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[ -f "$BIN" ] || { echo "error: built binary not found at $BIN"; exit 1; }

APP="$ROOT/dist/$APP_NAME.app"
echo "==> Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Validating Info.plist..."
plutil -lint "$APP/Contents/Info.plist"

SIGN_ID="G13ManagerSelfSigned"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    echo "==> Signing with stable self-signed identity '$SIGN_ID'..."
    codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
else
    echo "==> Ad-hoc signing (run scripts/make_signing_cert.sh for persistent grants)..."
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
codesign --verify --verbose=2 "$APP"

echo "==> Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP" "$INSTALL_DIR/$APP_NAME.app"

cat <<EOF

Done.

  Installed: $INSTALL_DIR/$APP_NAME.app
  Launch:    open "$INSTALL_DIR/$APP_NAME.app"

First run: grant Input Monitoring and Accessibility when prompted
(System Settings › Privacy & Security). If you rebuild and permissions
seem stuck, reset them with:

  tccutil reset ListenEvent $BUNDLE_ID
  tccutil reset Accessibility $BUNDLE_ID
EOF
