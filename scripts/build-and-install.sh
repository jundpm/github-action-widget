#!/bin/bash
# Build from source → install to ~/Applications → launch (restarts it if already running).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh "$@"
DEST="$HOME/Applications/GitHub Action Widget.app"
mkdir -p "$HOME/Applications"
pkill -x GitHubActionWidget 2>/dev/null || true
rm -rf "$DEST"
cp -R "build/GitHub Action Widget.app" "$DEST"
open "$DEST"
echo "✅ Installed and launched: $DEST"
