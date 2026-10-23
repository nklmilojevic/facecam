#!/usr/bin/env bash
# Builds the app and CLI, then packages dist/Facecam-<version>.dmg and dist/facecam-<version>-macos.tar.gz.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/FacecamBar.app/Contents/Info.plist)

mkdir -p dist
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R build/FacecamBar.app "$staging/Facecam.app"
ln -s /Applications "$staging/Applications"

dmg=dist/Facecam-${version}.dmg
rm -f "$dmg"
hdiutil create -volname "Facecam ${version}" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null

tarball=dist/facecam-${version}-macos.tar.gz
tar -czf "$tarball" -C build facecam

(cd dist && shasum -a 256 "$(basename "$dmg")" "$(basename "$tarball")" > SHA256SUMS)
echo "Packaged $dmg and $tarball"
