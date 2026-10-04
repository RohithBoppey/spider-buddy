#!/bin/bash
# Builds build/SpiderBuddy.app: compiles the Swift package, then bundles the binary,
# Info.plist, Resources/ and the sprite folders from ../frames-custom (preview/source files skipped).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/SpiderBuddy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sprites"
cp .build/release/SpiderBuddy "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp -R Resources/. "$APP/Contents/Resources/"   # speech lines, pixel font and its licence, Sounds/
mkdir -p "$APP/Contents/Frameworks"
ditto .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"   # in-app updates

for dir in ../frames-custom/*/; do
    name=$(basename "$dir")
    mkdir -p "$APP/Contents/Resources/Sprites/$name"
    find "$dir" -maxdepth 1 \( -name '*.png' -o -name 'anchors.json' \) ! -name '_*' -exec cp {} "$APP/Contents/Resources/Sprites/$name/" \;
done

# ad-hoc signature (no Apple Developer ID). Sparkle's helpers are signed first, then the app.
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
