#!/bin/bash
# Builds RAW Select and packages it into a double-clickable .app bundle.
# Requires only the Swift toolchain (Command Line Tools) – no full Xcode.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="RAW Select"
BUNDLE_ID="ch.anneler.rawselect"
VERSION="1.4"
EXECUTABLE="RAWSelect"

echo "▶︎ Building (release)…"
swift build -c release

BIN=".build/release/${EXECUTABLE}"
if [[ ! -f "$BIN" ]]; then
    echo "✗ Build produced no binary at $BIN" >&2
    exit 1
fi

echo "▶︎ Running self-test…"
"$BIN" --selftest    # aborts the build (set -e) if any logic check fails

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

# Install the plug-in on THIS machine too, so a build alone is enough while developing —
# the shipped path is BridgeInstaller, which does the same on app launch from the copy
# inside the bundle. Lightroom auto-scans this folder at startup, no "Add" needed.
#
# The plug-in in this repo is the SOURCE — the only copy to ever edit. Both the one below
# and the one in the bundle are build artifacts and get overwritten.
#
# Why copy instead of symlink: Lightroom cannot read the .lua files out of ~/Developer (it
# reads Info.lua once while you pick the folder, then every script load fails with "No
# script by the name Init.lua"), and a symlink resolves straight back there.
#
# Lightroom caches a plug-in's file list, so ADDING a .lua needs a remove + re-add in the
# Plug-in Manager. Changing existing ones only needs a Lightroom restart.
MODULES_DIR="${HOME}/Library/Application Support/Adobe/Lightroom/Modules"
if [[ -d "RAWSelectBridge.lrplugin" ]]; then
    echo "▶︎ Installing Lightroom bridge plug-in…"
    mkdir -p "${MODULES_DIR}"
    rm -rf "${MODULES_DIR}/RAWSelectBridge.lrplugin"
    cp -R "RAWSelectBridge.lrplugin" "${MODULES_DIR}/"
    echo "  → ${MODULES_DIR}/RAWSelectBridge.lrplugin"
fi

echo "✓ Done: $(pwd)/${APP_DIR}"
echo "  Start with:  open \"${APP_DIR}\""
