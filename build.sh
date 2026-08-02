#!/bin/zsh
# Builds Pastello.app into build/
set -euo pipefail
cd "${0:a:h}"

if [[ ! -f assets/AppIcon.icns ]]; then
  echo "→ generating icon…"
  swift tools/makeicon.swift assets
  iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns
fi

# Compile outside iCloud Drive: files there pick up extended attributes
# that codesign rejects ("detritus not allowed").
WORK="${TMPDIR:-/tmp}/PastelloBuild-EN"
APP="$WORK/Pastello.app"
rm -rf "$WORK"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ compiling…"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift \
  -o "$APP/Contents/MacOS/Pastello"

cp Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/menubar/MenuBarIcon.png assets/menubar/MenuBarIcon@2x.png "$APP/Contents/Resources/"

xattr -cr "$APP"
# Designated requirement based on the bundle id alone: the Accessibility
# permission granted once survives future builds (an ad-hoc signature would
# otherwise change its hash on every compile and macOS would invalidate it).
codesign --force --sign - --identifier it.foolica.pastello \
  -r='designated => identifier "it.foolica.pastello"' "$APP"

rm -rf build && mkdir -p build
ditto "$APP" "build/Pastello.app"

echo "✓ build complete and signed: $APP"
