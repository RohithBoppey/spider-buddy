#!/bin/bash
# Packages the app into dist/SpiderBuddy-<version>.dmg: a compressed disk image holding
# Spider Buddy.app and an Applications shortcut to drag it onto.
#   ./package.sh             build first, then package
#   ./package.sh --no-build  package the existing build/SpiderBuddy.app
set -euo pipefail
cd "$(dirname "$0")"

[ "${1:-}" = "--no-build" ] || ./build.sh

APP=build/SpiderBuddy.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=build/dmg
DMG=dist/SpiderBuddy-$VERSION.dmg

rm -rf "$STAGE"
mkdir -p "$STAGE" dist
ditto "$APP" "$STAGE/Spider Buddy.app"      # the name users see in Applications
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "Spider Buddy" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
echo "Packaged $(pwd)/$DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
