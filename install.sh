#!/bin/bash
# GitHub Action Widget — one-line installer
#   curl -fsSL https://raw.githubusercontent.com/jundpm/github-action-widget/main/install.sh | bash
#
# What it does (nothing else):
#   1. checks macOS 14+ and the GitHub CLI (`gh`) login the app uses for its token
#   2. downloads the latest release zip and installs it to ~/Applications
#   3. clears the download quarantine flag (the app is ad-hoc signed, not notarized)
#   4. launches the app
# Flags:  --from-source   build locally with Swift instead of downloading the release
set -euo pipefail

REPO="jundpm/github-action-widget"
APP_NAME="GitHub Action Widget.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/$APP_NAME"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || die "macOS 14 (Sonoma) or later is required (found $(sw_vers -productVersion))."

# The app reads its token from `gh auth token` — no separate login inside the app.
if ! command -v gh >/dev/null 2>&1; then
  warn "GitHub CLI (gh) not found. Install it:  brew install gh   then:  gh auth login"
elif ! gh auth status --hostname github.com >/dev/null 2>&1; then
  warn "gh is installed but not logged in. Run:  gh auth login"
else
  say "gh login found ($(gh api user -q .login 2>/dev/null || echo ok))"
fi

if [[ "${1:-}" == "--from-source" ]]; then
  command -v swift >/dev/null 2>&1 || die "Swift toolchain not found. Install Xcode or the Command Line Tools: xcode-select --install"
  tmp="$(mktemp -d)"
  say "Cloning $REPO …"
  git clone --depth 1 "https://github.com/$REPO.git" "$tmp/src" >/dev/null
  say "Building (universal) …"
  "$tmp/src/scripts/build-and-install.sh"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
url="https://github.com/$REPO/releases/latest/download/GitHubActionWidget.zip"
say "Downloading latest release …"
curl -fL --progress-bar "$url" -o "$tmp/app.zip" || die "Download failed: $url"
ditto -x -k "$tmp/app.zip" "$tmp"
[[ -d "$tmp/$APP_NAME" ]] || die "Unexpected archive layout."

pkill -x GitHubActionWidget 2>/dev/null || true
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
mv "$tmp/$APP_NAME" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

say "Installed to $DEST"
open "$DEST"
say "Launched. Look for the icon in your menu bar; pick repositories in Settings."
