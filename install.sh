#!/bin/sh
set -eu

REPO="nesetkab/medtner"
NAME="Medtner"

if [ -w /Applications ]; then
    DEST="/Applications"
else
    DEST="$HOME/Applications"
fi
APP="$DEST/$NAME.app"

if [ "${1:-}" = "uninstall" ]; then
    pkill -x "$NAME" 2>/dev/null || true
    rm -rf "/Applications/$NAME.app" "$HOME/Applications/$NAME.app"
    if [ "${2:-}" = "--all" ]; then
        rm -rf "$HOME/Library/Application Support/Medtner" "$HOME/Library/Caches/Medtner"
        defaults delete app.medtner 2>/dev/null || true
        echo "Medtner and all of its data are gone."
    else
        echo "Medtner removed. Your sign-in is kept in ~/Library/Application Support/Medtner."
        echo "Run with 'uninstall --all' to remove that too."
    fi
    exit 0
fi

if [ "$(uname -m)" != "arm64" ]; then
    echo "Medtner needs a Mac with Apple silicon (M1 or newer)."
    exit 1
fi

major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 15 ]; then
    echo "Medtner needs macOS 15 Sequoia or newer. This Mac has $(sw_vers -productVersion)."
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $NAME..."
curl -fsSL "https://github.com/$REPO/releases/latest/download/$NAME.zip" -o "$tmp/$NAME.zip"
ditto -x -k "$tmp/$NAME.zip" "$tmp"

pkill -x "$NAME" 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$APP"
ditto "$tmp/$NAME.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo "$NAME is installed in $DEST and opening now. Follow the steps in the window to connect Spotify."
