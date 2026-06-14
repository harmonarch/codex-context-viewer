#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex Context Monitor"
DMG_NAME="${DMG_NAME:-Codex-Context-Monitor}"
CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="$ROOT/dist"
APP_DIR="$ROOT/build/$APP_NAME.app"
STAGING_DIR="$ROOT/build/dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"

cd "$ROOT"
UNIVERSAL="${UNIVERSAL:-1}" CONFIGURATION="$CONFIGURATION" "$ROOT/scripts/build_app.sh" >/dev/null

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
