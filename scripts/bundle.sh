#!/usr/bin/env bash
# Builds universal release binaries and wraps FacecamBar in a menu-bar-only .app bundle.
# Version comes from $VERSION, else the latest git tag, else 0.0.0-dev.
set -euo pipefail
cd "$(dirname "$0")/.."

version=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0-dev)}
version=${version#v}
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)

arches=(--arch arm64 --arch x86_64)
swift build -c release "${arches[@]}" --product FacecamBar
swift build -c release "${arches[@]}" --product facecam
products=$(swift build -c release "${arches[@]}" --show-bin-path)

app=build/FacecamBar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/FacecamBar" "$app/Contents/MacOS/FacecamBar"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp "$products/facecam" build/facecam
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>FacecamBar</string>
    <key>CFBundleIdentifier</key><string>io.github.facecam.FacecamBar</string>
    <key>CFBundleName</key><string>Facecam</string>
    <key>CFBundleDisplayName</key><string>Facecam</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>CFBundleVersion</key><string>${build_number}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSCameraUsageDescription</key><string>Shows a live preview of your Elgato camera while you adjust it.</string>
</dict>
</plist>
PLIST
# Ad-hoc signature only: the app is not notarized.
codesign --force --sign - build/facecam
codesign --force --sign - "$app"
echo "Built $app and build/facecam (version $version)"
