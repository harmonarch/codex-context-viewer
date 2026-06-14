#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex Context Monitor"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64
else
  swift build -c "$CONFIGURATION"
fi

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  case "$CONFIGURATION" in
    debug) PRODUCT_CONFIGURATION="Debug" ;;
    release) PRODUCT_CONFIGURATION="Release" ;;
    *)
      echo "Unsupported universal build configuration: $CONFIGURATION" >&2
      exit 1
      ;;
  esac
  EXECUTABLE="$ROOT/.build/apple/Products/$PRODUCT_CONFIGURATION/CodexContextMonitor"
else
  EXECUTABLE="$ROOT/.build/$CONFIGURATION/CodexContextMonitor"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$EXECUTABLE" "$MACOS/Codex Context Monitor"
cp -R "$ROOT/Sources/CodexContextMonitor/Resources/." "$RESOURCES/"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Codex Context Monitor</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex-context-monitor</string>
  <key>CFBundleName</key>
  <string>Codex Context Monitor</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Context Monitor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Local app</string>
</dict>
</plist>
PLIST

echo "$APP_DIR"
