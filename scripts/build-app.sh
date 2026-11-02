#!/bin/bash
# Build "GitHub Action Widget.app" into build/ (universal: Apple Silicon + Intel).
# No Xcode project needed — swift build + hand-assembled bundle + ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
if [[ "${1:-}" == "--native" ]]; then ARCHS=(); fi   # faster local builds

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"
APP="build/GitHub Action Widget.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GitHubActionWidget" "$APP/Contents/MacOS/GitHubActionWidget"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
echo "✅ $APP"
