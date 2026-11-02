#!/bin/bash
# Build the universal app and zip it for a GitHub Release.
# Output: build/GitHubActionWidget.zip  (stable name so /releases/latest/download/... always works)
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
rm -f build/GitHubActionWidget.zip
ditto -c -k --keepParent "build/GitHub Action Widget.app" build/GitHubActionWidget.zip
shasum -a 256 build/GitHubActionWidget.zip | tee build/GitHubActionWidget.zip.sha256
