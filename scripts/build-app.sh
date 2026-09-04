#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

APP="build/Espacio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Espacio" "$APP/Contents/MacOS/Espacio"
cp Resources/Info.plist "$APP/Contents/Info.plist"
BUNDLE=".build/$CONFIG/Espacio_Espacio.bundle"
if ls "$BUNDLE"/*.lproj >/dev/null 2>&1; then
  cp -R "$BUNDLE"/*.lproj "$APP/Contents/Resources/"
elif ls "$BUNDLE"/Contents/Resources/*.lproj >/dev/null 2>&1; then
  cp -R "$BUNDLE"/Contents/Resources/*.lproj "$APP/Contents/Resources/"
else
  xcrun xcstringstool compile Sources/Espacio/Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f Resources/AppIcon.icns ]]; then
  swift scripts/make-icon.swift Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
echo "✔ $APP"
