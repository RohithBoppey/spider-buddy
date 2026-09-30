#!/bin/bash
# Prepares a release that installed copies will pick up through Sparkle:
#   ./release.sh 1.0.0 "What's new in this version"
# 1. sets the version in Info.plist
# 2. builds and packages dist/SpiderBuddy-<version>.dmg
# 3. signs the .dmg with the update key from your Keychain (account spider-buddy)
# 4. adds the version to ../appcast.xml, pointing at the GitHub Release download
# It publishes nothing: it prints the git and gh commands to run when you're ready.
set -euo pipefail
cd "$(dirname "$0")"

RELEASES_REPO="RohithBoppey/spider-buddy"   # where the .dmg is downloaded from (GitHub Releases)
SPARKLE_VERSION="2.10.0"
KEY_ACCOUNT="spider-buddy"

VERSION="${1:?usage: ./release.sh <version> \"release notes\"}"
NOTES="${2:?usage: ./release.sh <version> \"release notes\"}"
TAG="v$VERSION"
DMG="dist/SpiderBuddy-$VERSION.dmg"
URL="https://github.com/$RELEASES_REPO/releases/download/$TAG/SpiderBuddy-$VERSION.dmg"

if grep -q "<sparkle:version>$VERSION</sparkle:version>" ../appcast.xml; then
    echo "error: $VERSION is already in appcast.xml" >&2
    exit 1
fi

# Sparkle's command-line tools (git-ignored)
if [ ! -x .tools/sparkle/bin/sign_update ]; then
    mkdir -p .tools/sparkle
    curl -sSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
        | tar -xJ -C .tools/sparkle
fi

# 1. version (Sparkle compares CFBundleVersion; keep both the same)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Info.plist

# 2. build + dmg
pkill -x SpiderBuddy 2>/dev/null || true
./package.sh

# 3. signature: prints  sparkle:edSignature="..." length="..."
SIGNATURE=$(.tools/sparkle/bin/sign_update --account "$KEY_ACCOUNT" "$DMG")

# 4. appcast entry, newest first
python3 - "$VERSION" "$NOTES" "$URL" "$SIGNATURE" <<'EOF'
import sys
from email.utils import formatdate
from xml.sax.saxutils import escape

version, notes, url, signature = sys.argv[1:]
item = f"""    <item>
      <title>Version {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>{escape(notes)}</p>]]></description>
      <enclosure url="{url}" type="application/octet-stream" {signature} />
    </item>
"""
path = "../appcast.xml"
feed = open(path).read()
anchor = "    <language>en</language>\n"
feed = feed.replace(anchor, anchor + item, 1)
open(path, "w").write(feed)
EOF

cat <<EOF

Release $VERSION is ready: $(pwd)/$DMG
Publish it (in this order: the download must exist before the feed announces it):

  gh release create $TAG "app/$DMG" --repo $RELEASES_REPO --title "Spider Buddy $VERSION" --notes "$NOTES"
  git add app/Info.plist appcast.xml && git commit -m "Release $VERSION" && git push

EOF
