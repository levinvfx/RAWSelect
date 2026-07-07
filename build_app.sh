#!/bin/bash
# Builds RAW Select and packages it into a double-clickable .app bundle.
# Requires only the Swift toolchain (Command Line Tools) – no full Xcode.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="RAW Select"
BUNDLE_ID="ch.anneler.rawselect"
VERSION="1.0"
EXECUTABLE="RAWSelect"

echo "▶︎ Building (release)…"
swift build -c release

BIN=".build/release/${EXECUTABLE}"
if [[ ! -f "$BIN" ]]; then
    echo "✗ Build produced no binary at $BIN" >&2
    exit 1
fi

APP_DIR="${APP_NAME}.app"
echo "▶︎ Packaging ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "$BIN" "${APP_DIR}/Contents/MacOS/${EXECUTABLE}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>${EXECUTABLE}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# Ad-hoc code signature so first launch is smoother.
codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || echo "  (ad-hoc signing skipped)"

echo "✓ Done: $(pwd)/${APP_DIR}"
echo "  Start with:  open \"${APP_DIR}\""
