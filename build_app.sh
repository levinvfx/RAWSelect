#!/bin/bash
# Builds RAW Select and packages it into a double-clickable .app bundle.
# Requires only the Swift toolchain (Command Line Tools) – no full Xcode.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="RAW Select"
BUNDLE_ID="ch.anneler.rawselect"
VERSION="1.7"
EXECUTABLE="RAWSelect"

# Self-test runs on the DEBUG binary: SelfTest/SliderCal are dev-only (#if DEBUG) because their
# heavy expressions trip the release optimizer's type-checker. Debug proves the logic first.
echo "▶︎ Running self-test (debug binary)…"
swift build
".build/debug/${EXECUTABLE}" --selftest    # aborts the build (set -e) if any logic check fails

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

# App icon: regenerate the .icns from the source logo if possible, then bundle it.
if [[ -f "icon/Logo-App.png" ]]; then
    ( cd icon
      swiftc -O make_icon.swift -o make_icon 2>/dev/null && ./make_icon Logo-App.png icon_1024.png 2>/dev/null
      rm -rf AppIcon.iconset && mkdir AppIcon.iconset
      for s in 16 32 128 256 512; do d=$((s*2))
        sips -z $s $s icon_1024.png --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null 2>&1
        sips -z $d $d icon_1024.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null 2>&1
      done
      cp icon_1024.png "AppIcon.iconset/icon_512x512@2x.png"
      iconutil -c icns AppIcon.iconset -o AppIcon.icns 2>/dev/null ) || echo "  (icon regen skipped)"
fi
if [[ -f "icon/AppIcon.icns" ]]; then
    cp "icon/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    ICON_KEY=""
fi

# Brand logo (black + white variants) used by the Über/Credits tab and dark mode.
for logo in assets/Logo-Schwarz.png assets/Logo-Weiss.png; do
    [[ -f "$logo" ]] && cp "$logo" "${APP_DIR}/Contents/Resources/"
done

# The Lightroom bridge plug-in travels INSIDE the app. BridgeInstaller copies it into
# Lightroom's Modules folder on launch, so a download is all a user ever needs — and the
# app can never end up talking to an older plug-in than it expects. A stale one fails
# silently (it stops reporting the white balance), which is the worst kind of failure.
if [[ -d "RAWSelectBridge.lrplugin" ]]; then
    cp -R "RAWSelectBridge.lrplugin" "${APP_DIR}/Contents/Resources/"
fi

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
    ${ICON_KEY}
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key><string>RAW Select steuert Adobe Lightroom Classic, um ausgewählte RAW-Bilder als JPEG zu exportieren.</string>
</dict>
</plist>
PLIST

echo "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# Ad-hoc code signature so first launch is smoother.
codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || echo "  (ad-hoc signing skipped)"

# Keep the plug-in current at the STABLE path the user adds once in Lightroom's
# Zusatzmodul-Manager (see BridgeInstaller). NOT Lightroom's Modules folder: on LrC 15.x a
# Modules plug-in only half-loads (activated, but its scripts never run). The one-time manual
# "Add" from this path is what actually registers the scripts; the app just keeps files fresh.
#
# The plug-in in this repo is the SOURCE — the only copy to ever edit. The one below and the
# one in the bundle are build artifacts and get overwritten.
BRIDGE_DIR="${HOME}/Library/Application Support/RAW Select"
if [[ -d "RAWSelectBridge.lrplugin" ]]; then
    echo "▶︎ Updating Lightroom bridge plug-in (stable path)…"
    mkdir -p "${BRIDGE_DIR}"
    rm -rf "${BRIDGE_DIR}/RAWSelectBridge.lrplugin"
    cp -R "RAWSelectBridge.lrplugin" "${BRIDGE_DIR}/"
    echo "  → ${BRIDGE_DIR}/RAWSelectBridge.lrplugin"
    echo "  (einmalig in Lightroom: Datei → Zusatzmodul-Manager → Hinzufügen von diesem Pfad)"
fi

echo "✓ Done: $(pwd)/${APP_DIR}"
echo "  Start with:  open \"${APP_DIR}\""
