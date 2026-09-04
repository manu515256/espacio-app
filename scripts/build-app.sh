#!/bin/zsh
# Builds Espacio.app into build/ from the SwiftPM package (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

APP="build/Espacio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Espacio" "$APP/Contents/MacOS/Espacio"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f Resources/AppIcon.icns ]]; then
  swift scripts/make-icon.swift Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature (no developer identity on this machine). Stable enough for
# TCC as long as the bundle id and path stay the same.
codesign --force --sign - "$APP" >/dev/null
echo "✔ $APP"
