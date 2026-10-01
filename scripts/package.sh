#!/usr/bin/env bash
# Builds NotchTime.app (universal) and NotchTime.dmg into ./dist.
# Runs on macOS only (needs sips, iconutil, codesign, hdiutil).
set -euo pipefail

APP="NotchTime"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"

cd "$(dirname "$0")/.."

echo "▸ swift build (release, arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product "$APP"

BIN="$(find .build -type f -path '*Products/Release/'"$APP" | head -n1)"
if [[ -z "$BIN" ]]; then
  BIN="$(find .build -type f -path '*/release/'"$APP" | head -n1)"
fi
[[ -n "$BIN" ]] || { echo "binary not found"; exit 1; }
echo "▸ binary: $BIN"

rm -rf dist build/dmgroot build/icon.iconset
mkdir -p "dist/$APP.app/Contents/MacOS" "dist/$APP.app/Contents/Resources" build/icon.iconset build/dmgroot

cp "$BIN" "dist/$APP.app/Contents/MacOS/$APP"
chmod +x "dist/$APP.app/Contents/MacOS/$APP"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Packaging/Info.plist > "dist/$APP.app/Contents/Info.plist"
printf 'APPL????' > "dist/$APP.app/Contents/PkgInfo"

echo "▸ icon"
for s in 16 32 128 256 512; do
  sips -z $s $s Packaging/icon_1024.png --out "build/icon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Packaging/icon_1024.png --out "build/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/icon.iconset -o "dist/$APP.app/Contents/Resources/AppIcon.icns"

echo "▸ ad-hoc codesign"
codesign --force --deep --sign - --timestamp=none "dist/$APP.app"
codesign --verify --verbose=2 "dist/$APP.app"

echo "▸ dmg"
cp -R "dist/$APP.app" build/dmgroot/
ln -s /Applications build/dmgroot/Applications
hdiutil create -volname "$APP" -srcfolder build/dmgroot -ov -format UDZO "dist/$APP.dmg"

echo "▸ done"
ls -la dist
