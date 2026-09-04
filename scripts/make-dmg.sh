#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)

STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R build/Espacio.app "$STAGE/Espacio.app"
ln -s /Applications "$STAGE/Applications"

rm -f "build/Espacio-$VERSION.dmg" build/Espacio.dmg
hdiutil create -volname "Espacio" -srcfolder "$STAGE" -ov -format UDZO "build/Espacio-$VERSION.dmg" >/dev/null
cp "build/Espacio-$VERSION.dmg" build/Espacio.dmg
rm -rf "$STAGE"
echo "✔ build/Espacio-$VERSION.dmg"
