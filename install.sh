#!/bin/bash
# Installs (or reinstalls) the latest Spider Buddy into /Applications and launches it:
#   curl -fsSL https://raw.githubusercontent.com/RohithBoppey/spider-buddy/main/install.sh | bash
# Downloads the newest .dmg from GitHub Releases; after that, Sparkle keeps it up to date.
set -euo pipefail

REPO="RohithBoppey/spider-buddy"
APP_NAME="Spider Buddy.app"
DEST="/Applications/$APP_NAME"

fail() { echo "error: $*" >&2; exit 1; }

# macOS 13+ only
[ "$(uname -s)" = "Darwin" ] || fail "Spider Buddy only runs on macOS."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 13 ] || fail "Spider Buddy needs macOS 13 or later (you have $(sw_vers -productVersion))."

# Latest release's .dmg (no jq on stock macOS, so grep the JSON)
echo "🕷️  Looking up the latest release…"
RELEASE=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest") \
    || fail "couldn't reach GitHub (offline, or rate-limited: try again in an hour)."
DMG_URL=$(printf '%s' "$RELEASE" | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
VERSION=$(printf '%s' "$RELEASE" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$DMG_URL" ] || fail "the latest release has no .dmg attached."

TMP=$(mktemp -d)
MOUNT=""
cleanup() {
    [ -n "$MOUNT" ] && hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

echo "⬇️  Downloading Spider Buddy ${VERSION}…"
curl -fL --progress-bar -o "$TMP/SpiderBuddy.dmg" "$DMG_URL"

# Mount point is the last tab-separated field of hdiutil's output
MOUNT=$(hdiutil attach -nobrowse -readonly -noautoopen "$TMP/SpiderBuddy.dmg" | tail -1 | awk -F'\t' '{print $NF}')
[ -d "$MOUNT/$APP_NAME" ] || fail "the disk image doesn't contain $APP_NAME."

# /Applications like any other app; it needs admin rights, so without them fall back to
# ~/Applications (the per-user Applications folder Spotlight and Launchpad also index).
# Sort this out before quitting the running copy, so a failed password changes nothing.
SUDO=""
if [ ! -w /Applications ]; then
    echo "🔐 /Applications needs an administrator password:"
    if sudo -v 2>/dev/null; then
        SUDO="sudo"
    else
        echo "   No admin rights, installing to ~/Applications instead."
        DEST="$HOME/Applications/$APP_NAME"
        mkdir -p "$HOME/Applications"
    fi
fi
echo "📦 Installing to $(dirname "$DEST")…"
pkill -x SpiderBuddy 2>/dev/null || true
$SUDO rm -rf "$DEST"
$SUDO ditto "$MOUNT/$APP_NAME" "$DEST"
# Owned by the user, so Sparkle can update it without asking for a password
[ -z "$SUDO" ] || sudo chown -R "$(id -un)" "$DEST"
# The app isn't notarized; curl doesn't quarantine, but clear it in case something did
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

open "$DEST"
echo "✅ Installed Spider Buddy ${VERSION}. Look for 🕷️ in your menu bar."
